#!/bin/bash
# clod's test suite: builds images through the launcher, as a Linux user would,
# and checks the containers it runs. CI runs it on fresh GitHub runners, a few
# tests per job.
#
# It needs Linux, and a Docker it can have to itself: it builds, replaces and
# prunes the clod images on the Docker it uses, and starts containers with that
# Docker's socket mounted. Run it on a CI runner or a throwaway VM; --yes
# confirms that outside CI. Each run gets a fresh HOME, so ~/.clod is left
# alone, and the Docker CLI keeps its config (and so its context).
#
#   test/run.sh [--yes] [TEST|GROUP...]   run them, or every test
#   test/run.sh --list                    list the groups and tests
#
# Tests run in the order listed. Each starts in an empty directory; the home is
# shared, so later tests see the images and variants earlier ones made, but
# each also runs alone.

# shellcheck disable=SC2016 # single-quoted scripts expand in the container

repo=$(cd "$(dirname "$0")/.." && pwd -P)

lint_tests='lint'
base_tests='env run-command empty-workspace scratch refuses-home claude codex statusline
  port docker-socket envrc volume-home default new-shared command-line multi-stage
  combine rebuild remove-image prune completion'
classic_tests='classic'
# The bundled variants: go and sudo are checked together as go+sudo, and docker
# by docker-socket.
variant_names='browser dotnet lamp python rust go+sudo'
variants_tests=$(for v in $variant_names; do printf 'variant-%s ' "$v"; done)

# Prints the tests in group $1, or fails if there's no such group.
group_tests() {
  case $1 in
    lint) echo "$lint_tests" ;;
    base) echo "$base_tests" ;;
    classic) echo "$classic_tests" ;;
    variants) echo "$variants_tests" ;;
    *) return 1 ;;
  esac
}
all_tests="$lint_tests $base_tests $classic_tests $variants_tests"

usage() {
  sed -n '/^#   test/s/^# *//p' "$0"
}

list() {
  local g
  for g in lint base classic variants; do
    printf '%s:\n' "$g"
    # shellcheck disable=SC2046 # test names don't contain spaces or globs
    printf '  %s\n' $(group_tests "$g")
  done
}

# The tests. Each runs in a subshell with -e and pipefail, in an empty
# directory, with clod on PATH.

# Matches its input like grep -q, but reads all of it: grep -q exits at the
# first match, and a command still writing into the pipe then fails. The
# helpers return their failure, so a failed test names the line calling them.
has() {
  grep "$@" >/dev/null || return 1
}

# Runs a command, failing unless it exits with status $1.
exits() {
  local want=$1 got=0
  shift
  "$@" || got=$?
  [[ $got == "$want" ]] || return 1
}

test_lint() {
  cd "$repo"
  shellcheck clod entrypoint.sh shared/statusline.sh docs/statusline-svg.sh test/run.sh
}

test_env() {
  clod env
}

test_run_command() {
  echo hello > from-host
  clod bash -c '
    set -e
    test "$(id -u)" = "'"$(id -u)"'"
    test "$(cat /proc/1/comm)" = tini
    test "$USER" = claude && test "$TMPDIR" = /tmp && test "$EDITOR" = vim && test "$PAGER" = less
    test "$(cat /workspace/from-host)" = hello
    test -f /etc/claude-code/managed-settings.json
    test -r /etc/clod/.claude/rules/clod.md
    touch /workspace/from-container
    git --version; gh --version | head -1; node --version; python3 --version; jq --version; fd --version
  '
  test "$(stat -c %u from-container)" = "$(id -u)"
}

test_empty_workspace() {
  touch file
  clod bash -c true 2>&1 | tee out
  if grep -q 'workspace is empty' out; then false; fi
  docker run --rm -e CLOD_WORKSPACE_FILES=1 -v "$(mktemp -d):/workspace" clod bash -c true 2>&1 |
    has 'workspace is empty'
}

test_scratch() {
  touch from-host
  echo 'export FOO=bar' > .envrc
  direnv allow
  volumes=$(docker volume ls -q | wc -l)
  clod -s bash -c '
    set -e
    test "$CLOD_SCRATCH" = 1
    test -z "$(ls -A /workspace)"
    test -z "${FOO:-}"
    touch /workspace/written
  ' 2>&1 | tee out
  if grep -q 'workspace is empty' out; then false; fi
  test ! -e written
  test "$(docker volume ls -q | wc -l)" = "$volumes"
  clod -s env | has '^scratch:'
  if clod -s env | has '^envrc:'; then false; fi
  exits 2 clod -s --docker bash -c true
  cd ~
  clod -s bash -c true
}

test_refuses_home() {
  cd ~
  exits 1 clod bash -c true
}

test_claude() {
  clod claude --version | tee out
  grep -q 'Claude Code' out
  # a symlink into the container's paths, so dangling out here
  test -L ~/.clod/homes/default/.local/bin/claude
}

test_codex() {
  clod codex --version | tee out
  grep -qi codex out
}

test_statusline() {
  echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"session_id":"ci","prompt_id":"p1",
         "context_window":{"total_input_tokens":48200,"total_output_tokens":12100,"used_percentage":42,
           "current_usage":{"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},
         "cost":{"total_lines_added":120,"total_lines_removed":35},
         "rate_limits":{"five_hour":{"used_percentage":12}}}' > input.json
  clod bash -c 'bash /etc/claude-code/statusline.sh < /workspace/input.json' |
    sed 's/\x1b\[[0-9;]*m//g' | tee out
  grep -q 'default@clod' out
  grep -q 'Opus' out
  grep -q '42%' out
}

test_port() {
  echo served > index.html
  clod -P 8000 bash -c 'timeout 60 python3 -m http.server 8000 --bind 0.0.0.0' &
  for _ in $(seq 30); do
    curl -fs http://127.0.0.1:8000/index.html > out && break
    sleep 2
  done
  kill $! 2>/dev/null || true
  grep -q served out
}

test_docker_socket() {
  echo sibling > from-host
  clod bash -c 'test ! -e /var/run/docker.sock'
  if clod env | has '^docker:'; then false; fi
  clod --docker env | has '^docker:'
  clod --docker bash -c true 2>&1 | has 'clod has no docker CLI'
  clod -i docker --docker bash -c '
    set -e
    test "$(id -un)" = claude
    docker compose version && docker buildx version
    test -r /etc/clod/.claude/rules/docker.md
    docker ps
    test "$(docker run --rm --entrypoint cat -v "$CLOD_HOST_WORKSPACE:/w" clod /w/from-host)" = sibling
  ' 2>&1 | tee out
  if grep -q 'no docker CLI' out; then false; fi
}

test_envrc() {
  printf 'export FOO=bar MULTI="a\nb" CLOD_HOME=from-envrc\n' > .envrc
  exits 1 clod env
  direnv allow
  clod env 2>&1 | tee out
  grep -q '^FOO=bar$' out
  grep -q 'skipping multi-line variable MULTI' out
  grep -q '^home: *from-envrc' out
  echo 'export CLOD_PORTS=5000' >> .envrc
  direnv allow
  clod env | has '^ports: .*5000'
  if CLOD_PORTS='' clod env | has '^ports:'; then false; fi
  if clod -P '' env | has '^ports:'; then false; fi
  clod bash -c 'test "$FOO" = bar && test -z "${MULTI:-}" && test "$CLOD_HOME" = from-envrc'
}

test_volume_home() {
  docker volume rm -f clod-home-vtest >/dev/null
  clod -H vol:vtest bash -c '
    set -e
    test "$CLOD_HOME" = vol:vtest
    test "$(stat -c %U ~)" = claude
    echo kept > ~/kept
    mkdir ~/owned && chown claude:claude ~/owned
  '
  clod -H vol:vtest bash -c 'test "$(cat ~/kept)" = kept'
  test ! -e ~/.clod/homes/vol:vtest
  clod -H vol:vtest env | has '^home: *vol:vtest (Docker volume clod-home-vtest)'
  clod -H vol:vtest homes | has '^\* vol:vtest '
  exits 1 clod -H vol:./x env
  docker volume rm clod-home-vtest >/dev/null
}

test_default() {
  exits 1 clod default image no-such-image
  clod default image python
  clod default image | has '^image  *python .*config'
  clod default command bash
  clod -i clod -- -c 'echo from-default-command' | has from-default-command
  clod default command --reset
  clod default command | has '^command  *claude .*built in'
  clod env | has '^image: *clod-python'
  clod default image clod
  clod env | has '^image: *clod$'
}

test_new_shared() {
  clod new-shared
  test -f ~/.clod/shared/statusline.sh
  clod new-shared | has 'has everything in the starter'
  clod env | has '^shared: *~/.clod/shared'
  rm ~/.clod/shared/statusline.sh
  clod new-shared | has 'missing  *statusline.sh'
  cp "$repo/container.md" ~/.clod/shared/CLAUDE.md
  clod new-shared | has 'describes the container'
  clod --force new-shared
  test -f ~/.clod/shared/statusline.sh
  ls -d ~/.clod/shared.bak-*
  rm -r ~/.clod/shared ~/.clod/shared.bak-*
}

test_command_line() {
  exits 2 clod -p 'a prompt'
  exits 1 clod -H ~ bash -c true
  exits 2 clod --resume
  exits 2 clod 'a prompt'
  exits 1 clod build mine
  exits 2 clod prune extra
  exits 2 clod env extra
  exits 2 clod new-image a b c
  clod -i clod-python env | has '^image: *clod-python (.*images/python)'
  clod --help | has '^Usage: clod'
  clod --version | has '^clod '
  clod -H other -i python -P 3000:8080 env | tee out
  grep -q '^home: *other' out
  grep -q '^image: *clod-python' out
  grep -q '^ports: *127.0.0.1:3000 → 8080$' out
  clod bash -c true
  clod images | has '^\* clod  *built'
  clod homes | has '^\* default'
  rm -rf ~/.clod/images/mine ~/.clod/images/starter
  clod new-image mine go
  grep -q '^FROM \$BASE$' ~/.clod/images/mine/Dockerfile
  clod new-image starter
  clod images | has 'starter .*~/.clod/images/starter'
  clod --skip-build bash -c true 2>&1 | has 'running clod as built'
}

test_multi_stage() {
  mkdir -p ~/.clod/images/one ~/.clod/images/stages
  printf 'FROM clod\n' > ~/.clod/images/one/Dockerfile
  printf 'FROM debian:trixie AS build\nFROM clod-one\n' > ~/.clod/images/stages/Dockerfile
  clod -i stages bash -c true
  clod images | has '^  stages  *built'
  echo 'RUN true' >> ~/.clod/images/one/Dockerfile
  clod images | has '^  one  *stale'
  clod images | has '^  stages  *stale'
  clod -i stages bash -c true 2>&1 | tee out
  grep -q 'building clod-one' out
  grep -q 'building clod-stages' out
  clod images | has '^  stages  *built'
  clod images stages | has '^stages  *built  *debian:trixie, clod-one  '
  clod images stages | has '^one  *built  *clod  '
}

# Writes variants first and second, which take their base as BASE and record
# the order they were built in.
order_variants() {
  mkdir -p ~/.clod/images/first ~/.clod/images/second
  printf 'ARG BASE=clod\nFROM $BASE\nRUN echo first > /tmp/order\n' > ~/.clod/images/first/Dockerfile
  printf 'ARG BASE=clod\nFROM $BASE\nRUN echo second >> /tmp/order\n' > ~/.clod/images/second/Dockerfile
}

test_combine() {
  order_variants
  mkdir -p ~/.clod/images/third ~/.clod/images/fixed
  # braces, and no default: it only ever goes on top of another
  printf 'ARG BASE\nFROM ${BASE}\nRUN echo third >> /tmp/order\n' > ~/.clod/images/third/Dockerfile
  printf 'FROM clod\n' > ~/.clod/images/fixed/Dockerfile
  clod -i first+second env | has '^image: *clod-first.second '
  clod -i first+second bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond")"'
  clod images | has '^  first.second  *built'
  clod -i clod-first.second --skip-build bash -c true
  echo 'RUN true' >> ~/.clod/images/first/Dockerfile
  clod images | has '^  first.second  *stale'
  clod -i first+second bash -c true 2>&1 | has 'building clod-first.second'
  exits 1 clod -i first+fixed env 2>out
  grep -q "fixed can't go on top" out
  exits 1 clod -i first+nope env
  for name in first+ +first first++second; do
    exits 1 clod -i "$name" env 2>out
    grep -q 'invalid image name' out
  done
  exits 1 clod default image first+nope
  clod -i fixed+first env | has '^image: *clod-fixed.first '
  clod -i first.second env | has '^image: *clod-first.second '
  # three: third is built on the combination clod-first.second
  clod -i first+second+third bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond\nthird")"'
  clod images | has '^  first.second.third  *built'
  clod images first+second+third > out
  test "$(awk 'NR > 1 { print $1 }' out)" = "$(printf 'first.second.third\nfirst.second\nfirst\nclod')"
  has '^first.second  *built  *clod-first  ' < out
  has '^first.second.third  .*/images/third/Dockerfile$' < out
  exits 1 clod images nope
  exits 2 clod images first second
  clod default image first+second
  clod env | has '^image: *clod-first.second '
  clod images | has '^\* first.second  *built'
  clod default image --reset
  # a variant on a combination rebuilds when a variant in it changes
  rm -rf ~/.clod/images/ontop
  clod new-image ontop first+second
  grep -q '^FROM clod-first.second$' ~/.clod/images/ontop/Dockerfile
  clod -i ontop bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond")"'
  clod images | has '^  ontop  *built'
  echo 'RUN true' >> ~/.clod/images/second/Dockerfile
  clod images | has '^  ontop  *stale'
  clod -i ontop bash -c true 2>&1 | tee out
  grep -q 'building clod-first.second' out
  grep -q 'building clod-ontop' out
}

# rebuild replaces every image in the chain and prunes the old ones. It runs a
# copy of clod whose base Dockerfile only writes a file, since rebuilding the
# real one without the cache takes half a minute; that replaces the clod image,
# which the next test to use it rebuilds from the layer cache.
test_rebuild() {
  local t i before=() after=()
  [[ -f ~/.clod/images/first/Dockerfile ]] || order_variants
  mkdir standin
  cp "$repo/clod" "$repo/entrypoint.sh" "$repo/container.md" standin/
  printf 'FROM debian:trixie\nRUN date > /built\n' > standin/Dockerfile
  standin/clod -i first+second build
  test "$(standin/clod -i first+second build 2>&1)" = 'clod: first.second is up to date'
  for t in clod clod-first clod-first.second; do before+=("$(docker image inspect -f '{{.Id}}' "$t")"); done
  standin/clod -i first+second rebuild
  for t in clod clod-first clod-first.second; do after+=("$(docker image inspect -f '{{.Id}}' "$t")"); done
  for i in 0 1 2; do
    test "${before[i]}" != "${after[i]}"
    if docker image inspect "${before[i]}" >/dev/null 2>&1; then false; fi
  done
  # build rebuilds only what changed, and prunes what it replaced
  echo 'RUN true' >> ~/.clod/images/second/Dockerfile
  standin/clod -i first+second build 2>&1 | tee out
  if grep -q 'building clod-first\.\.\.' out; then false; fi
  grep -q 'building clod-first.second' out
  test "$(docker image inspect -f '{{.Id}}' clod-first)" = "${after[1]}"
  if docker image inspect "${after[2]}" >/dev/null 2>&1; then false; fi
  # build takes names, which win over -i, and builds a shared base once
  exits 1 clod build no-such
  echo 'RUN true' >> ~/.clod/images/first/Dockerfile
  clod -i no-such build first first+second 2>&1 | tee out
  test "$(grep -c 'building clod-first\.\.\.' out)" = 1
  grep -q 'building clod-first.second' out
  test "$(clod -i no-such build first first+second)" = \
    "$(printf 'clod: first is up to date\nclod: first.second is up to date')"
}

test_remove_image() {
  mkdir -p ~/.clod/images/gone ~/.clod/images/top ~/.clod/images/a-very-long-variant-name
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' gone > ~/.clod/images/gone/Dockerfile
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' top > ~/.clod/images/top/Dockerfile
  printf 'FROM clod\n' > ~/.clod/images/a-very-long-variant-name/Dockerfile
  clod -i gone+top build
  clod -i top build
  clod __complete remove-image '' | has -x gone.top
  if clod __complete remove-image gone '' | grep -qx gone; then false; fi
  clod images | has '^  a-very-long-variant-name  -'
  exits 1 clod -i no-such remove-image
  exits 1 clod remove-image no-such
  exits 1 clod remove-image gone no-such
  docker image inspect clod-gone >/dev/null
  # gone.top is built on gone; a name wins over -i
  clod -i top remove-image gone | has 'clod-gone'
  if docker image inspect clod-gone >/dev/null 2>&1; then false; fi
  docker image inspect clod-top >/dev/null
  clod -i top remove-image | has -x 'removed clod-top'
  clod images | has '^  gone  *-'
  rm -r ~/.clod/images/gone
  clod images | has '^  gone\.top  *built  *gone + top (no Dockerfile)'
  clod remove-image gone+top | has -x 'removed clod-gone.top'
  if clod images | grep -q gone; then false; fi
}

# prune removes the stale images, those built on others first, and keeps the
# rest.
test_prune() {
  mkdir -p ~/.clod/images/keep ~/.clod/images/old
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' keep > ~/.clod/images/keep/Dockerfile
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' old > ~/.clod/images/old/Dockerfile
  clod -i keep build
  clod -i old+keep build
  clod prune
  test "$(clod prune)" = 'clod: no stale images'
  echo 'LABEL changed=1' >> ~/.clod/images/old/Dockerfile
  clod images | has '^  old\.keep  *stale'
  test "$(clod prune)" = "$(printf 'removed clod-old.keep\nremoved clod-old')"
  docker image inspect clod-keep >/dev/null
  clod images | has '^  keep  *built'
  clod images | has '^  old  *-'
  if clod images | grep -q 'old\.keep'; then false; fi
  # an image a container uses, even a stopped one, stays, and shows as in use
  docker rm -f clod-test-in-use >/dev/null 2>&1 || true
  docker create --name clod-test-in-use clod-keep >/dev/null
  echo 'LABEL changed=1' >> ~/.clod/images/keep/Dockerfile
  clod images | has '^  keep  *stale, in use  '
  clod images | has '^in use '
  test "$(clod prune)" = 'kept clod-keep: a container uses it (docker ps -a lists them)'
  exits 1 clod remove-image keep
  docker image inspect clod-keep >/dev/null
  docker rm clod-test-in-use >/dev/null
  test "$(clod prune)" = 'removed clod-keep'
}

# Tab completion: clod __complete's candidates, and the shim it prints, in bash
# and (if installed) zsh. Needs no Docker.
test_completion() {
  mkdir -p ~/.clod/homes/work ~/.clod/images/plain
  printf 'FROM clod\n' > ~/.clod/images/plain/Dockerfile
  test "$(clod __complete 'new-')" = "$(printf 'new-image\nnew-shared')"
  test "$(clod __complete --sk)" = --skip-build
  clod __complete images '' | has -x plain
  clod __complete build plain '' | has -x plain
  clod __complete -i '' | has -x go
  clod __complete -i '' | has -x clod
  test "$(clod __complete -i go+su)" = go+sudo
  # after +: not a variant already there, nor one built FROM clod
  if clod __complete -i go+ | grep -qxE 'go\+(go|plain)'; then false; fi
  clod __complete -H w | has -x work
  test -z "$(clod __complete -H ./w)"
  # bash splits words at colons
  clod __complete -H vol : work '' | has -x claude
  clod __complete -P 3000 : 5173 '' | has -x claude
  test "$(clod __complete default co)" = command
  clod __complete default command '' | has -x codex
  if clod __complete new-image mine '' | grep -qx clod; then false; fi
  # exit status 1: the word is a file name, which the shell completes
  if clod __complete claude --re; then false; fi
  if clod __complete -- ''; then false; fi
  if clod __complete -H ./w; then false; fi
  if clod __complete install ''; then false; fi
  test -z "$(clod __complete -P '')"
  clod __complete -P ''
  printf '%s\n' 'eval "$(clod completion)"' 'COMP_WORDS=(clod -i go+su); COMP_CWORD=2; _clod' \
    'echo "${COMPREPLY[*]}"' > shim-test
  test "$(bash shim-test)" = go+sudo
  if command -v zsh >/dev/null; then
    # outside a completion widget, compadd and _files stand in as printers
    printf '%s\n' 'eval "$(clod completion)"' \
      'compadd() { print -r -- ${(P)2}; }; _files() { print files; }' \
      'words=(clod -i go+su); CURRENT=3; _clod' \
      "words=(clod claude ''); CURRENT=3; _clod" > shim-test
    test "$(zsh -f shim-test 2>/dev/null)" = "$(printf 'go+sudo\nfiles')"
  fi
}

# Homebrew's docker on macOS has no buildx, so clod's builds there use the
# classic builder; the base image, and a variant on top of another through
# BASE, must build without BuildKit.
test_classic() {
  DOCKER_BUILDKIT=0 docker build -q -t clod-classic "$repo"
  DOCKER_BUILDKIT=0 docker build -q --build-arg BASE=clod-classic "$repo/images/sudo"
}

# Builds variant (or combination) $1 and checks its tools in the container.
test_variant() {
  local check
  case $1 in
    browser)
      check='echo "<h1>clod</h1>" > /tmp/page.html &&
        chromium --headless --screenshot=/tmp/shot.png --window-size=800,600 file:///tmp/page.html &&
        test -s /tmp/shot.png && test -r /etc/clod/.claude/rules/browser.md' ;;
    dotnet) check='dotnet --version' ;;
    lamp) check='php -v && composer --version && apache2 -v && mariadb --version' ;;
    python) check='test "$UV_LINK_MODE" = copy && uv --version && gcc --version | head -1 && python3-config --includes' ;;
    rust) check='cargo new -q /tmp/hello && cd /tmp/hello && cargo run -q' ;;
    go+sudo) check='go version && test "$(sudo -n whoami)" = root && test -r /etc/clod/.claude/rules/sudo.md' ;;
  esac
  clod -i "$1" bash -c "set -e; $check"
}

# Collects the tests the arguments name, in the order given.
yes=''
selected=()
for arg in "$@"; do
  case $arg in
    -h|--help) usage; exit 0 ;;
    --list) list; exit 0 ;;
    -y|--yes) yes=1 ;;
    -*) echo "test/run.sh: unknown option $arg" >&2; usage >&2; exit 2 ;;
    *)
      if names=$(group_tests "$arg"); then
        # shellcheck disable=SC2206 # test names don't contain spaces or globs
        selected+=($names)
      elif [[ " $all_tests " == *" $arg "* ]]; then
        selected+=("$arg")
      else
        echo "test/run.sh: no test or group named '$arg' (test/run.sh --list)" >&2
        exit 2
      fi
      ;;
  esac
done
# shellcheck disable=SC2206 # test names don't contain spaces or globs
(( ${#selected[@]} )) || selected=($all_tests)

if [[ $OSTYPE != linux* ]]; then
  echo "test/run.sh: the tests need Linux (run them in a Linux VM)" >&2
  exit 1
fi
needs_docker=''
for t in "${selected[@]}"; do
  [[ $t == lint || $t == completion ]] || needs_docker=1
done
if [[ -n $needs_docker ]]; then
  if [[ -z $CI && -z $yes ]]; then
    echo "test/run.sh: the tests build, replace and prune clod images on the Docker they use, and" >&2
    echo "mount its socket into containers. Run them on a CI runner or a throwaway VM, with --yes." >&2
    exit 1
  fi
  if ! docker version >/dev/null 2>&1; then
    echo "test/run.sh: can't reach Docker" >&2
    exit 1
  fi
fi

# A fresh HOME, with clod installed on PATH as a user would install it. The
# Docker CLI keeps its config, and so its context.
work=$(mktemp -d)
export DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
export HOME=$work/home
mkdir -p "$HOME/.local/bin"
export PATH="$HOME/.local/bin:$PATH"
while IFS= read -r v; do unset "$v"; done < <(compgen -v CLOD_)
"$repo/clod" install >/dev/null
if [[ $(readlink "$HOME/.local/bin/clod") != "$repo/clod" || $(command -v clod) != "$HOME/.local/bin/clod" ]]; then
  echo "test/run.sh: clod install didn't link $HOME/.local/bin/clod to $repo/clod" >&2
  exit 1
fi

# Reports that test $1 failed at line $2, from the test's own shell only.
fail_report() {
  [[ $BASHPID == "$test_shell" ]] || return 0
  echo "$1 failed at line $2:$(sed -n "$2p" "$repo/test/run.sh")" >&2
}

# GitHub Actions folds each test's output into a group.
github=${GITHUB_ACTIONS:-}
failed=()
for t in "${selected[@]}"; do
  [[ -n $github ]] && echo "::group::$t"
  dir=$(mktemp -d "$work/$t.XXXX")
  (
    set -eEo pipefail
    # -E carries the trap into command substitutions and pipelines too, where a
    # command may fail without failing the test, so only the test's own shell
    # reports. The name is expanded now, since a test may have its own $t. The
    # trap stays on one line: LINENO counts on through a multi-line one.
    test_shell=$BASHPID
    trap 'fail_report "'"$t"'" "$LINENO"' ERR
    cd "$dir"
    case $t in
      variant-*) test_variant "${t#variant-}" ;;
      *) "test_${t//-/_}" ;;
    esac
  )
  status=$?
  [[ -n $github ]] && echo "::endgroup::"
  if (( status )); then
    failed+=("$t")
    if [[ -n $github ]]; then echo "::error::$t failed"; else echo "FAIL $t"; fi
  else
    echo "ok   $t"
  fi
done

echo
if (( ${#failed[@]} )); then
  echo "${#failed[@]} of ${#selected[@]} failed: ${failed[*]}"
  echo "(their directories and the home are in $work)"
  exit 1
fi
echo "all ${#selected[@]} passed"
rm -rf "$work"
