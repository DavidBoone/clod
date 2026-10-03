#!/bin/bash
# clod's test suite: builds images through the launcher, as a Linux user would,
# and checks the containers it runs. CI runs it on a fresh GitHub runner, one
# group per job.
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
# each also runs alone. A test that can't run here exits 77 and is skipped.

# shellcheck disable=SC2016 # single-quoted scripts expand in the container

repo=$(cd "$(dirname "$0")/.." && pwd -P)

lint_tests='lint'
base_tests='env run-command empty-workspace refuses-home claude codex statusline
  port docker-socket envrc creds default new-shared command-line multi-stage
  combine rebuild shared-docker'
classic_tests='classic'
variant_names='browser docker dotnet go lamp python rust sudo go+sudo'
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

# Prints the docker tag clod gives image $1 for this user: the name itself, or
# NAME:<uid> for a uid other than 1000.
tagged() {
  if [[ $(id -u) == 1000 ]]; then echo "$1"; else echo "$1:$(id -u)"; fi
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
    test "$(cat /workspace/from-host)" = hello
    test -f /etc/claude-code/managed-settings.json
    test -s /etc/clod/.claude/rules/clod.md
    touch /workspace/from-container
    git --version; gh --version | head -1; node --version; python3 --version; jq --version; fd --version
  '
  test "$(stat -c %u from-container)" = "$(id -u)"
}

test_empty_workspace() {
  touch file
  clod bash -c true 2>&1 | tee out
  if grep -q 'workspace is empty' out; then false; fi
  docker run --rm -e CLOD_WORKSPACE_FILES=1 -v "$(mktemp -d):/workspace" "$(tagged clod)" bash -c true 2>&1 |
    has 'workspace is empty'
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
    docker ps
    test "$(docker run --rm --entrypoint cat -v "$CLOD_HOST_WORKSPACE:/w" '"$(tagged clod)"' /w/from-host)" = sibling
  ' 2>&1 | tee out
  if grep -q 'no docker CLI' out; then false; fi
}

test_envrc() {
  printf 'FOO=bar\nMULTI="a\nb"\nCLOD_HOME=from-envrc\n' > .clod.envrc
  clod env 2>&1 | tee out
  grep -q '^FOO=bar$' out
  grep -q 'skipping multi-line variable MULTI' out
  grep -q '^home: *from-envrc' out
  clod bash -c 'test "$FOO" = bar && test -z "${MULTI:-}" && test "$CLOD_HOME" = from-envrc'
}

test_creds() {
  mkdir -p ~/.clod/homes/owner/.claude
  echo '{"token":"ci"}' > ~/.clod/homes/owner/.claude/.credentials.json
  CLOD_HOME=borrower CLOD_CREDS=owner clod bash -c 'cat ~/.claude/.credentials.json; touch ~/.claude/written' | tee out
  grep -q '"ci"' out
  test "$(stat -c %u ~/.clod/homes/borrower/.claude)" = "$(id -u)"
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

# rebuild replaces every image in the chain and prunes the old ones.
test_rebuild() {
  local t i before=() after=()
  [[ -f ~/.clod/images/first/Dockerfile ]] || order_variants
  clod -i first+second bash -c true
  for t in clod clod-first clod-first.second; do before+=("$(docker image inspect -f '{{.Id}}' "$(tagged "$t")")"); done
  clod -i first+second rebuild
  for t in clod clod-first clod-first.second; do after+=("$(docker image inspect -f '{{.Id}}' "$(tagged "$t")")"); done
  for i in 0 1 2; do
    test "${before[i]}" != "${after[i]}"
    if docker image inspect "${before[i]}" >/dev/null 2>&1; then false; fi
  done
}

# Users sharing a Docker keep their own images: a uid-1000 user gets the plain
# tags and leaves this user's alone. Needs a uid other than 1000 and
# passwordless sudo to act as the other user.
test_shared_docker() {
  local mine other other_home
  if [[ $(id -u) == 1000 ]] || ! sudo -n true 2>/dev/null; then
    echo "needs a uid other than 1000 and passwordless sudo"
    exit 77
  fi
  clod bash -c true
  clod env | has "^user: .*images tagged :$(id -u)$"
  mine=$(docker image inspect -f '{{.Id}}' "clod:$(id -u)")
  other=$(getent passwd 1000 | cut -d: -f1)
  [[ -n $other ]] || { other=other; sudo useradd -u 1000 "$other"; }
  sudo usermod -aG docker "$other"
  sudo rm -rf /opt/clod-test
  sudo cp -r "$repo" /opt/clod-test
  sudo chmod -R a+rX /opt/clod-test
  other_home=$(sudo -u "$other" mktemp -d)
  sudo -u "$other" env HOME="$other_home" bash -c '
    set -e
    cd "$(mktemp -d)"
    mkdir -p ~/.clod/images/mine
    printf "ARG BASE=clod\nFROM \$BASE\nRUN touch /tmp/mine\n" > ~/.clod/images/mine/Dockerfile
    /opt/clod-test/clod env | grep -q "^user: *claude as 1000:[0-9]*$"
    /opt/clod-test/clod -i mine bash -c "test \$(id -u) = 1000 && test -f /tmp/mine"
  '
  docker image inspect clod clod-mine >/dev/null
  test "$(docker image inspect -f '{{.Id}}' "clod:$(id -u)")" = "$mine"
  clod bash -c "test \$(id -u) = $(id -u)" 2>&1 | tee out
  if grep -q building out; then false; fi
}

# Homebrew's docker on macOS has no buildx, so clod's builds there use the
# classic builder; the base image, and a variant on top of another through
# BASE or from a Dockerfile on stdin (as clod builds one for a uid other than
# 1000), must build without BuildKit.
test_classic() {
  DOCKER_BUILDKIT=0 docker build -q -t clod-classic "$repo"
  DOCKER_BUILDKIT=0 docker build -q --build-arg BASE=clod-classic "$repo/images/sudo"
  sed 's/^FROM .*/FROM clod-classic/' "$repo/images/sudo/Dockerfile" |
    DOCKER_BUILDKIT=0 docker build -q -f - "$repo/images/sudo"
}

# Builds variant (or combination) $1 and checks its tools in the container.
test_variant() {
  local check
  case $1 in
    browser)
      check='echo "<h1>clod</h1>" > /tmp/page.html &&
        chromium --headless --screenshot=/tmp/shot.png --window-size=800,600 file:///tmp/page.html &&
        test -s /tmp/shot.png && test -s /etc/clod/.claude/rules/browser.md' ;;
    docker)
      check='docker --version && docker compose version && docker buildx version &&
        test -s /etc/clod/.claude/rules/docker.md' ;;
    dotnet) check='dotnet --version' ;;
    go) check='go version' ;;
    lamp) check='php -v && composer --version && apache2 -v && mariadb --version' ;;
    python) check='uv --version && gcc --version | head -1 && python3-config --includes' ;;
    rust) check='cargo new -q /tmp/hello && cd /tmp/hello && cargo run -q' ;;
    sudo) check='test "$(sudo -n whoami)" = root && test -s /etc/clod/.claude/rules/sudo.md' ;;
    go+sudo) check='go version && test "$(sudo -n whoami)" = root' ;;
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
  [[ $t == lint ]] || needs_docker=1
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

# GitHub Actions folds each test's output into a group.
github=${GITHUB_ACTIONS:-}
failed=() skipped=()
for t in "${selected[@]}"; do
  [[ -n $github ]] && echo "::group::$t"
  dir=$(mktemp -d "$work/$t.XXXX")
  (
    set -eEo pipefail
    trap 'echo "$t failed at line $LINENO:$(sed -n "${LINENO}p" "$repo/test/run.sh")" >&2' ERR
    cd "$dir"
    case $t in
      variant-*) test_variant "${t#variant-}" ;;
      *) "test_${t//-/_}" ;;
    esac
  )
  status=$?
  [[ -n $github ]] && echo "::endgroup::"
  if (( status == 77 )); then
    skipped+=("$t")
    echo "skip $t"
  elif (( status )); then
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
passed=$(( ${#selected[@]} - ${#skipped[@]} ))
echo "all $passed passed${skipped[0]+, ${#skipped[@]} skipped: ${skipped[*]}}"
rm -rf "$work"
