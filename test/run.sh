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
base_tests='env run-command terminal mount-paths scratch workspace refuses-home claude codex statusline
  port docker-socket envrc volume-home home-copy home-new volume-workspace default shared command-line
  multi-stage combine rebuild image-rm image-prune completion'
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

test_terminal() {
  export TERM=xterm-256color TERM_PROGRAM=iTerm.app TERM_PROGRAM_VERSION=3.7.3 \
    LC_TERMINAL=iTerm2 LC_TERMINAL_VERSION=3.7.3 COLORTERM=truecolor
  # in a terminal they go in, all but TERM
  cat > check <<'EOF'
set -e
test "$TERM" = xterm
test "$TERM_PROGRAM" = iTerm.app && test "$TERM_PROGRAM_VERSION" = 3.7.3
test "$LC_TERMINAL" = iTerm2 && test "$LC_TERMINAL_VERSION" = 3.7.3
test "$COLORTERM" = truecolor
EOF
  script -qec 'clod bash /workspace/check' /dev/null < /dev/null
  # without one they don't
  clod bash -c '
    test -z "${TERM_PROGRAM:-}${TERM_PROGRAM_VERSION:-}${LC_TERMINAL:-}${LC_TERMINAL_VERSION:-}${COLORTERM:-}"
  ' < /dev/null
}

test_mount_paths() {
  mkdir 'a,"b'
  echo hello > 'a,"b/from-host'
  clod home new './h,"1' >/dev/null
  clod -H './h,"1' -w 'a,"b' bash -c '
    set -e
    test "$(cat /workspace/from-host)" = hello
    touch ~/from-container
    if touch /etc/claude-code/x 2>/dev/null; then false; fi
  '
  test -f 'h,"1/from-container'
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
  clod -s --docker bash -c 'test -z "${CLOD_HOST_WORKSPACE:-}"'
  cd ~
  clod -s bash -c true
}

test_workspace() {
  local here=$PWD
  mkdir proj
  echo from-proj > proj/file
  echo 'export FOO=proj' > proj/.envrc
  echo 'export FOO=here' > .envrc
  direnv allow proj
  direnv allow
  clod -w proj env | has "^workspace: *$here/proj\$"
  clod -w proj env | has '^envrc: .*/proj/.envrc$'
  clod -w proj bash -c '
    set -e
    test "$(cat /workspace/file)" = from-proj
    test "$FOO" = proj
    test "$CLOD_WORKSPACE" = "'"$here/proj"'"
  '
  exits 1 clod -w nope bash -c true
  exits 1 clod -w nope env
  clod -w nope home >/dev/null
  exits 2 clod -s -w proj bash -c true
  exits 1 clod -w ~ bash -c true 2>&1 | has 'refusing to mount'
  mkdir -p ~/.clod/homes/x
  exits 1 clod -w ~/.clod/homes/x bash -c true 2>&1 | has 'refusing to mount'
  cd ~
  clod -w "$here/proj" bash -c 'test "$(cat /workspace/file)" = from-proj && test "$FOO" = proj'
  # a volume workspace is claude's, kept between runs, and reads no .envrc
  cd "$here/proj"
  docker volume rm -f clod-workspace-wtest >/dev/null
  clod -w vol:wtest bash -c '
    set -e
    test "$CLOD_WORKSPACE" = vol:wtest
    test "$(stat -c %U /workspace)" = claude
    test -z "${FOO:-}"
    echo kept > /workspace/kept
  '
  clod -w vol:wtest bash -c 'test "$(cat /workspace/kept)" = kept'
  clod -w vol:wtest env | has '^workspace: *vol:wtest (Docker volume clod-workspace-wtest)'
  if clod -w vol:wtest env | has '^envrc:'; then false; fi
  exits 1 clod -w vol:./x env
  docker volume rm clod-workspace-wtest >/dev/null
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
         "workspace":{"current_dir":"/workspace"},
         "context_window":{"total_input_tokens":48200,"total_output_tokens":12100,"used_percentage":42,
           "current_usage":{"cache_creation_input_tokens":0,"cache_read_input_tokens":0}},
         "cost":{"total_lines_added":120,"total_lines_removed":35},
         "rate_limits":{"five_hour":{"used_percentage":12}}}' > input.json
  git init -q -b main .
  # the model, clod's home, image and ports, and git on one line; the meters on the next
  clod -P 5173 -P 6000/udp bash -c 'bash /etc/claude-code/statusline.sh < /workspace/input.json' |
    sed 's/\x1b\[[0-9;]*m//g; s/\x1b\]8;;[^\x07]*\x07//g' | tee out
  test "$(wc -l < out)" = 2
  head -1 out | has '✦ Opus .*⌂ default ⬢ clod  ⇄ :5173  .*ᚴ main ±[0-9]'
  if grep -q 6000 out; then false; fi
  tail -1 out | has '42%'
  # inside .git, where git status fails, it still shows both lines
  sed -i 's|"/workspace"|"/workspace/.git"|' input.json
  clod bash -c 'bash /etc/claude-code/statusline.sh < /workspace/input.json' > out
  test "$(wc -l < out)" = 2
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
  mkdir sub
  clod -i docker --docker -w sub bash -c 'test "$CLOD_HOST_WORKSPACE" = "'"$PWD/sub"'"'
  # a volume workspace has no host path; the agent's containers mount it by name
  docker volume rm -f clod-workspace-dtest >/dev/null
  clod -i docker --docker -w vol:dtest bash -c '
    set -e
    test -z "${CLOD_HOST_WORKSPACE:-}"
    echo sibling > /workspace/from-agent
    test "$(docker run --rm --entrypoint cat -v clod-workspace-dtest:/w clod /w/from-agent)" = sibling
  '
  docker volume rm clod-workspace-dtest >/dev/null
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
  clod home new from-envrc >/dev/null
  clod bash -c 'test "$FOO" = bar && test -z "${MULTI:-}" && test "$CLOD_HOME" = from-envrc'
}

test_volume_home() {
  docker volume rm -f clod-home-vtest >/dev/null
  clod home new vol:vtest >/dev/null
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
  clod -H vol:vtest home | has '^\* vol:vtest '
  exits 1 clod -H vol:./x env
  # home rm takes names and vol:NAME, not paths, asks first, and needs --force
  # without a terminal
  exits 2 clod home rm ./x 2>&1 | has 'delete the home ./x yourself'
  exits 2 clod --force home rm vol:vtest ~/.clod/homes/x
  exits 2 clod home rm -f vol:vtest 2>&1 | has "options go before the command"
  # a name it doesn't know removes none of them
  exits 1 clod --force home rm vol:vtest vol:no-such
  docker volume inspect clod-home-vtest >/dev/null
  exits 1 clod home rm vol:vtest < /dev/null 2>&1 | tee out
  has 'no terminal' < out
  if grep -q deleting out; then false; fi
  docker volume inspect clod-home-vtest >/dev/null
  # Docker won't remove a volume a container uses
  docker rm -f clod-test-home >/dev/null 2>&1 || true
  docker create --name clod-test-home -v clod-home-vtest:/h clod >/dev/null
  exits 1 clod --force home rm vol:vtest 2>&1 | has 'a container uses vol:vtest'
  docker rm clod-test-home >/dev/null
  docker volume inspect clod-home-vtest >/dev/null
  clod --force home rm vol:vtest | has -x 'removed vol:vtest (Docker volume clod-home-vtest)'
  if docker volume inspect clod-home-vtest >/dev/null 2>&1; then false; fi
  if clod home | grep -q vtest; then false; fi
  # a directory home, the same way
  mkdir -p ~/.clod/homes/dtest/.claude
  exits 1 clod home rm dtest < /dev/null 2>&1 | has 'no terminal'
  test -d ~/.clod/homes/dtest
  docker create --name clod-test-home --mount "type=bind,src=$HOME/.clod/homes/dtest,dst=/h" clod >/dev/null
  exits 1 clod --force home rm dtest 2>&1 | has 'a container uses dtest'
  docker rm clod-test-home >/dev/null
  test -d ~/.clod/homes/dtest
  clod --force home rm dtest dtest | has -x "removed dtest (the folder ~/.clod/homes/dtest)"
  test ! -e ~/.clod/homes/dtest
  exits 1 clod --force home rm dtest 2>&1 | has 'no home dtest'
}

# home cp and mv, between directory and volume homes both ways: the copy is
# claude's, and they refuse a missing source, an existing destination, a home a
# container uses and a directory that's off limits.
test_home_copy() {
  docker volume rm -f clod-home-cp1 clod-home-cp2 >/dev/null
  docker rm -f clod-test-cp clod-test-cp-dir clod-test-cp-gone >/dev/null 2>&1 || true
  mkdir -p ~/.clod/homes/src/.config
  echo hi > ~/.clod/homes/src/.config/f
  chmod 600 ~/.clod/homes/src/.config/f
  test "$(clod home cp src vol:cp1)" = 'copied src to vol:cp1'
  test -f ~/.clod/homes/src/.config/f
  clod -H vol:cp1 bash -c '
    set -e
    test "$(cat ~/.config/f)" = hi
    test "$(stat -c %U ~ ~/.config ~/.config/f | sort -u)" = claude
    test "$(stat -c %a ~/.config/f)" = 600
    touch ~/written
  '
  test "$(clod home cp vol:cp1 back)" = 'copied vol:cp1 to back'
  test "$(cat ~/.clod/homes/back/.config/f)" = hi
  test -O ~/.clod/homes/back/written
  test "$(clod home mv vol:cp1 vol:cp2)" = 'moved vol:cp1 to vol:cp2'
  if docker volume inspect clod-home-cp1 >/dev/null 2>&1; then false; fi
  clod -H vol:cp2 bash -c 'test -f ~/written'
  test "$(clod home mv back vol:cp1)" = 'moved back to vol:cp1'
  test ! -e ~/.clod/homes/back
  clod -H vol:cp1 bash -c 'test -f ~/written'
  # a directory moved to a directory is renamed
  test "$(clod home mv src ./moved/here)" = 'moved src to ./moved/here'
  test ! -e ~/.clod/homes/src
  test -f moved/here/.config/f
  exits 2 clod home cp src
  exits 2 clod home mv a b c
  exits 2 clod home cp -f a 2>&1 | has "options go before the command"
  exits 1 clod home cp nope vol:x 2>&1 | has -x 'clod: no home nope (clod home lists them)'
  exits 1 clod home cp vol:nope x 2>&1 | has 'no home vol:nope'
  exits 1 clod home cp vol:cp1 vol:cp2 2>&1 | has 'already a home vol:cp2'
  mkdir -p ~/.clod/homes/taken
  exits 1 clod home mv vol:cp1 taken 2>&1 | has 'taken already exists'
  exits 1 clod home cp ./moved ./moved/here/inside 2>&1 | has 'into itself'
  exits 1 clod home mv ~ vol:x 2>&1 | has "won't touch"
  exits 1 clod home cp ~/.clod/homes vol:x 2>&1 | has "won't touch"
  exits 1 clod home cp vol:cp1 ~/.clod 2>&1 | has "won't touch"
  # neither a source nor a destination a container uses, even a stopped one
  docker create --name clod-test-cp -v clod-home-cp1:/h clod >/dev/null
  exits 1 clod home mv vol:cp1 elsewhere 2>&1 | has 'a container uses vol:cp1'
  docker create --name clod-test-cp-dir --mount "type=bind,src=$PWD/moved/here,dst=/h" clod >/dev/null
  exits 1 clod home cp ./moved/here vol:x 2>&1 | has 'a container uses'
  mkdir gone
  docker create --name clod-test-cp-gone --mount "type=bind,src=$PWD/gone,dst=/h" clod >/dev/null
  rmdir gone
  exits 1 clod home cp vol:cp2 ./gone 2>&1 | has 'a container uses'
  docker rm clod-test-cp clod-test-cp-dir clod-test-cp-gone >/dev/null
  test -f moved/here/.config/f
  test ! -e gone
  docker volume inspect clod-home-cp1 >/dev/null
  if docker volume inspect clod-home-x >/dev/null 2>&1; then false; fi
  clod --force home rm vol:cp1 vol:cp2 >/dev/null
}

# A run asks before creating a home that doesn't exist, and without a terminal
# fails; clod home new creates one.
test_home_new() {
  docker volume rm -f clod-home-ntest >/dev/null
  exits 1 clod -H fresh bash -c true < /dev/null 2>&1 |
    has -x "clod: there's no home fresh; clod home new fresh creates it"
  test ! -e ~/.clod/homes/fresh
  exits 1 clod -H vol:ntest bash -c true < /dev/null 2>&1 | has 'no home vol:ntest'
  if docker volume inspect clod-home-ntest >/dev/null 2>&1; then false; fi
  # in a terminal it asks
  printf 'n\n' | script -qec 'clod -H fresh bash -c true' /dev/null > out || true
  has 'no home fresh; create it' < out
  test ! -e ~/.clod/homes/fresh
  printf 'y\n' | script -qec 'clod -H fresh bash -c true' /dev/null > out
  test -d ~/.clod/homes/fresh
  clod -H fresh bash -c true
  test "$(clod home new made)" = 'created home made'
  clod -H made bash -c 'test "$(stat -c %U ~)" = claude'
  exits 1 clod home new made 2>&1 | has 'made already exists'
  test "$(clod home new vol:ntest)" = 'created home vol:ntest'
  clod -H vol:ntest bash -c 'test "$(stat -c %U ~)" = claude'
  exits 1 clod home new vol:ntest 2>&1 | has 'already a home vol:ntest'
  exits 2 clod home new
  exits 2 clod home new a b
  clod --force home rm vol:ntest >/dev/null
}

test_volume_workspace() {
  docker volume rm -f clod-workspace-one clod-workspace-two clod-workspace-three >/dev/null
  clod workspace | has 'no volume workspaces'
  clod -w vol:one bash -c true
  clod -w vol:two bash -c true
  clod workspace | has '^  vol:one  *-$'
  clod -w vol:two workspace | tee out
  has '^\* vol:two ' < out
  has '^\* used here' < out
  exits 2 clod workspace rm
  exits 2 clod workspace ls
  exits 2 clod workspace rm -f one 2>&1 | has "options go before the command"
  # a name it doesn't know removes none of them
  exits 1 clod --force workspace rm one no-such
  docker volume inspect clod-workspace-one >/dev/null
  exits 1 clod workspace rm one < /dev/null 2>&1 | tee out
  has 'no terminal' < out
  if grep -q deleting out; then false; fi
  docker volume inspect clod-workspace-one >/dev/null
  # in a terminal it lists the volumes and asks: n or no answer keeps them, y
  # removes them
  docker volume create clod-workspace-three >/dev/null
  printf 'n\n' | exits 1 script -qec 'clod workspace rm three' /dev/null > out
  has 'vol:three (Docker volume clod-workspace-three)' < out
  has 'Delete? \[y/N\]' < out
  has 'nothing deleted' < out
  docker volume inspect clod-workspace-three >/dev/null
  printf '\n' | exits 1 script -qec 'clod workspace rm three' /dev/null | has 'nothing deleted'
  docker volume inspect clod-workspace-three >/dev/null
  printf 'y\n' | script -qec 'clod workspace rm three' /dev/null |
    has 'removed vol:three (clod-workspace-three)'
  if docker volume inspect clod-workspace-three >/dev/null 2>&1; then false; fi
  # Docker won't remove a volume a container uses
  docker rm -f clod-test-volume >/dev/null 2>&1 || true
  docker create --name clod-test-volume -v clod-workspace-two:/w clod >/dev/null
  clod workspace | has '^  vol:two  *in use$'
  exits 1 clod --force workspace rm two 2>&1 | has 'a container uses vol:two'
  docker rm clod-test-volume >/dev/null
  test "$(clod --force workspace rm one vol:two)" = \
    "$(printf 'removed vol:one (clod-workspace-one)\nremoved vol:two (clod-workspace-two)')"
  clod workspace | has 'no volume workspaces'
}

test_default() {
  exits 1 clod default image no-such-image
  clod default image python
  clod default image | has '^image  *python .*config'
  clod default command bash
  clod -i clod -- -c 'echo from-default-command' | has from-default-command
  clod default command --reset
  clod default command | has '^command  *claude .*built in'
  clod env | has '^image: *python '
  clod default image clod
  clod env | has '^image: *clod$'
}

test_shared() {
  exits 1 clod shared diff
  exits 2 clod shared
  clod shared new
  test -f ~/.clod/shared/statusline.sh
  clod shared new | has 'has everything in the starter'
  clod shared diff | has 'same as the starter'
  clod env | has '^shared: *~/.clod/shared'
  rm ~/.clod/shared/statusline.sh
  echo '# mine' >> ~/.clod/shared/managed-settings.json
  clod shared new | has 'missing  *statusline.sh'
  exits 1 clod shared diff | has '^Only in .*/shared: statusline.sh$'
  exits 1 clod shared diff | has -x '+# mine'
  # diff's trouble, status 2, is clod's
  mkdir bin
  printf '#!/bin/sh\nexit 2\n' > bin/diff
  chmod +x bin/diff
  PATH=$PWD/bin:$PATH exits 2 clod shared diff
  cp "$repo/container.md" ~/.clod/shared/CLAUDE.md
  clod shared new | has 'describes the container'
  clod --force shared new
  test -f ~/.clod/shared/statusline.sh
  ls -d ~/.clod/shared.bak-*
  rm -r ~/.clod/shared ~/.clod/shared.bak-*
}

test_command_line() {
  exits 2 clod -p 'a prompt'
  exits 1 clod -H ~ bash -c true
  exits 2 clod --resume
  exits 2 clod 'a prompt'
  exits 1 clod image build mine
  exits 2 clod image prune extra
  exits 2 clod env extra
  exits 2 clod image new a b c
  exits 2 clod image new
  for name in Mine -mine mine_ my.image; do
    exits 2 clod image new "$name" 2>&1 | has 'invalid image name'
  done
  exits 2 clod image show
  exits 2 clod image nope
  exits 2 clod home ls
  for old in images homes new-image remove-image prune new-shared; do
    exits 2 clod "$old" 2>&1 | has "unknown command '$old'"
  done
  # build and rebuild still work, with a note naming image build
  exits 1 clod build mine 2>&1 | has 'clod build is deprecated; use clod image build$'
  exits 1 clod rebuild mine 2>&1 | has 'use clod image rebuild$'
  clod -i clod-python env | has '^image: *python (.*images/python)'
  clod --help | has '^Usage: clod'
  clod --version | has '^clod '
  clod -H other -i python -P 3000:8080 env | tee out
  grep -q '^home: *other' out
  grep -q '^image: *python ' out
  grep -q '^ports: *127.0.0.1:3000 → 8080$' out
  clod -P 6000/udp env | has '^ports: *127.0.0.1:6000 → 6000/udp$'
  clod bash -c true
  clod image | has '^\* clod  *built'
  clod home | has '^\* default'
  rm -rf ~/.clod/images/mine ~/.clod/images/starter
  clod image new mine go
  grep -q '^FROM \$BASE$' ~/.clod/images/mine/Dockerfile
  clod image new starter
  clod image | has 'starter .*~/.clod/images/starter'
  clod --skip-build bash -c true 2>&1 | has 'running clod as built'
}

test_multi_stage() {
  mkdir -p ~/.clod/images/one ~/.clod/images/stages
  printf 'FROM clod\n' > ~/.clod/images/one/Dockerfile
  printf 'FROM debian:trixie AS build\nFROM clod-one\n' > ~/.clod/images/stages/Dockerfile
  clod -i stages bash -c true
  clod image | has '^  stages  *built'
  echo 'RUN true' >> ~/.clod/images/one/Dockerfile
  clod image | has '^  one  *stale'
  clod image | has '^  stages  *stale'
  clod -i stages bash -c true 2>&1 | tee out
  grep -q 'building one\.\.\.' out
  grep -q 'building stages\.\.\.' out
  clod image | has '^  stages  *built'
  clod image show stages | has '^stages  *built  *debian:trixie, one  '
  clod image show stages | has '^one  *built  *clod  '
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
  clod -i first+second env | has '^image: *first+second '
  clod -i first+second bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond")"'
  clod -i first+second bash -c 'test "$CLOD_IMAGE" = first+second' 2>&1 | has '^clod ⌂ .* ⬢ first+second · '
  clod image | has '^  first+second  *built'
  clod -i clod-first.second --skip-build bash -c true
  echo 'RUN true' >> ~/.clod/images/first/Dockerfile
  clod image | has '^  first+second  *stale'
  clod -i first+second bash -c true 2>&1 | has 'building first+second\.\.\.'
  exits 1 clod -i first+fixed env 2>out
  grep -q "fixed can't go on top" out
  exits 1 clod -i first+nope env
  for name in first+ +first first++second; do
    exits 1 clod -i "$name" env 2>out
    grep -q 'invalid image name' out
  done
  exits 1 clod default image first+nope
  clod -i fixed+first env | has '^image: *fixed+first '
  # the Docker image's name works too
  clod -i first.second env | has '^image: *first+second '
  clod -i clod-first.second env | has '^image: *first+second '
  # three: third is built on the combination first+second
  clod -i first+second+third bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond\nthird")"'
  clod image | has '^  first+second+third  *built'
  clod image show first+second+third > out
  test "$(awk 'NR > 1 { print $1 }' out)" = "$(printf 'first+second+third\nfirst+second\nfirst\nclod')"
  has '^first+second  *built  *first  ' < out
  has '^first+second+third  .*/images/third/Dockerfile$' < out
  exits 1 clod image show nope
  exits 2 clod image show first second
  clod default image first+second
  clod env | has '^image: *first+second '
  clod image | has '^\* first+second  *built'
  clod default image --reset
  # a variant on a combination rebuilds when a variant in it changes
  rm -rf ~/.clod/images/ontop
  clod image new ontop first+second
  grep -q '^FROM clod-first\.second$' ~/.clod/images/ontop/Dockerfile
  grep -q 'FROM names first+second as Docker does: clod-first\.second\.$' ~/.clod/images/ontop/Dockerfile
  clod -i ontop bash -c 'test "$(cat /tmp/order)" = "$(printf "first\nsecond")"'
  clod image | has '^  ontop  *built'
  echo 'RUN true' >> ~/.clod/images/second/Dockerfile
  clod image | has '^  ontop  *stale'
  clod -i ontop bash -c true 2>&1 | tee out
  grep -q 'building first+second\.\.\.' out
  grep -q 'building ontop\.\.\.' out
}

# image rebuild replaces every image in the chain and prunes the old ones. It
# runs a copy of clod whose base Dockerfile only writes a file, since rebuilding
# the real one without the cache takes half a minute; that replaces the clod
# image, which the next test to use it rebuilds from the layer cache.
test_rebuild() {
  local t i before=() after=()
  [[ -f ~/.clod/images/first/Dockerfile ]] || order_variants
  mkdir standin
  cp "$repo/clod" "$repo/entrypoint.sh" "$repo/container.md" standin/
  printf 'FROM debian:trixie\nRUN date > /built\n' > standin/Dockerfile
  standin/clod -i first+second image build
  test "$(standin/clod -i first+second image build 2>&1)" = 'clod: first+second is up to date'
  for t in clod clod-first clod-first.second; do before+=("$(docker image inspect -f '{{.Id}}' "$t")"); done
  standin/clod -i first+second image rebuild
  for t in clod clod-first clod-first.second; do after+=("$(docker image inspect -f '{{.Id}}' "$t")"); done
  for i in 0 1 2; do
    test "${before[i]}" != "${after[i]}"
    if docker image inspect "${before[i]}" >/dev/null 2>&1; then false; fi
  done
  # image build rebuilds only what changed, and prunes what it replaced
  echo 'RUN true' >> ~/.clod/images/second/Dockerfile
  standin/clod -i first+second image build 2>&1 | tee out
  if grep -q 'building first\.\.\.' out; then false; fi
  grep -q 'building first+second\.\.\.' out
  test "$(docker image inspect -f '{{.Id}}' clod-first)" = "${after[1]}"
  if docker image inspect "${after[2]}" >/dev/null 2>&1; then false; fi
  # image build takes names, which win over -i, and builds a shared base once
  exits 1 clod image build no-such
  echo 'RUN true' >> ~/.clod/images/first/Dockerfile
  clod -i no-such image build first first+second 2>&1 | tee out
  test "$(grep -c 'building first\.\.\.' out)" = 1
  grep -q 'building first+second\.\.\.' out
  test "$(clod -i no-such image build first first+second)" = \
    "$(printf 'clod: first is up to date\nclod: first+second is up to date')"
  # the build alias, with its note on stderr only
  test "$(clod build first 2>/dev/null)" = 'clod: first is up to date'
}

test_image_rm() {
  mkdir -p ~/.clod/images/gone ~/.clod/images/top ~/.clod/images/a-very-long-variant-name
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' gone > ~/.clod/images/gone/Dockerfile
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' top > ~/.clod/images/top/Dockerfile
  printf 'FROM clod\n' > ~/.clod/images/a-very-long-variant-name/Dockerfile
  clod -i gone+top image build
  clod -i top image build
  clod __complete image rm '' | has -x gone+top
  if clod __complete image rm gone '' | grep -qx gone; then false; fi
  clod image | has '^  a-very-long-variant-name  -'
  exits 1 clod -i no-such image rm
  exits 1 clod image rm no-such
  exits 1 clod image rm gone no-such
  docker image inspect clod-gone >/dev/null
  # gone+top is built on gone; a name wins over -i
  clod -i top image rm gone | has '^removed .*gone'
  if docker image inspect clod-gone >/dev/null 2>&1; then false; fi
  docker image inspect clod-top >/dev/null
  clod -i top image rm | has -x 'removed top'
  clod image | has '^  gone  *-'
  rm -r ~/.clod/images/gone
  clod image | has '^  gone+top  *built  *gone + top (no Dockerfile)'
  clod image rm gone+top | has -x 'removed gone+top'
  if clod image | grep -q gone; then false; fi
}

# image prune removes the stale images, those built on others first, and keeps the
# rest.
test_image_prune() {
  mkdir -p ~/.clod/images/keep ~/.clod/images/old
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' keep > ~/.clod/images/keep/Dockerfile
  printf 'ARG BASE=clod\nFROM $BASE\nLABEL test=%s\n' old > ~/.clod/images/old/Dockerfile
  clod -i keep image build
  clod -i old+keep image build
  clod image prune
  test "$(clod image prune)" = 'clod: no stale images'
  echo 'LABEL changed=1' >> ~/.clod/images/old/Dockerfile
  clod image | has '^  old+keep  *stale'
  test "$(clod image prune)" = "$(printf 'removed old+keep\nremoved old')"
  docker image inspect clod-keep >/dev/null
  clod image | has '^  keep  *built'
  clod image | has '^  old  *-'
  if clod image | grep -q 'old+keep'; then false; fi
  # an image a container uses, even a stopped one, stays, and shows as in use
  docker rm -f clod-test-in-use >/dev/null 2>&1 || true
  docker create --name clod-test-in-use clod-keep >/dev/null
  echo 'LABEL changed=1' >> ~/.clod/images/keep/Dockerfile
  clod image | has '^  keep  *stale, in use  '
  clod image | has '^in use '
  test "$(clod image prune)" = 'kept keep: a container uses it (docker ps -a lists them)'
  exits 1 clod image rm keep
  docker image inspect clod-keep >/dev/null
  docker rm clod-test-in-use >/dev/null
  test "$(clod image prune)" = 'removed keep'
}

# Tab completion: clod __complete's candidates, and the shim it prints, typed
# into bash and (if installed) zsh. Needs no Docker.
test_completion() {
  mkdir -p ~/.clod/homes/work ~/.clod/images/plain
  printf 'FROM clod\n' > ~/.clod/images/plain/Dockerfile
  test "$(clod __complete --sk)" = --skip-build
  # the nouns and their verbs; build and rebuild only after image
  test "$(clod __complete i)" = "$(printf 'image\ninstall')"
  if clod __complete '' | grep -qxE 'build|rebuild'; then false; fi
  test "$(clod __complete image '')" = "$(printf 'show\nnew\nbuild\nrebuild\nrm\nprune')"
  test "$(clod __complete image re)" = rebuild
  test "$(clod __complete home '')" = "$(printf 'new\ncp\nmv\nrm')"
  test -z "$(clod __complete home new '')"
  if clod __complete home new ./x; then false; fi
  test "$(clod __complete workspace '')" = rm
  test "$(clod __complete shared '')" = "$(printf 'new\ndiff')"
  test -z "$(clod __complete shared new '')"
  test -z "$(clod __complete image prune '')"
  clod __complete image show '' | has -x plain
  test -z "$(clod __complete image show plain '')"
  clod __complete image build '' | has -x plain
  clod __complete image rebuild go '' | has -x plain
  if clod __complete image build plain '' | grep -qx plain; then false; fi
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
  clod __complete image new mine '' | has -x go
  if clod __complete image new mine '' | grep -qx clod; then false; fi
  test -z "$(clod __complete image new mine go '')"
  # exit status 1: the word is a file name, which the shell completes
  if clod __complete claude --re; then false; fi
  if clod __complete -- ''; then false; fi
  if clod __complete -H ./w; then false; fi
  if clod __complete install ''; then false; fi
  if clod __complete -w ''; then false; fi
  test "$(clod __complete --wor)" = --workspace
  test -z "$(clod __complete -P '')"
  clod __complete -P ''
  # The shim in real shells, which split words differently: bash at = and :,
  # zsh not at all. A stand-in docker lists the volumes. Directories complete
  # with a / in bash only.
  mkdir proj bin
  printf '%s\n' '#!/bin/bash' \
    '[[ "$1 $2" == "volume ls" ]] && printf "%s\n" clod-home-vhome clod-workspace-play' > bin/docker
  chmod +x bin/docker
  PATH=$PWD/bin:$PATH clod __complete home rm '' | has -x vol:vhome
  PATH=$PWD/bin:$PATH clod __complete home rm '' | has -x work
  # a home named already isn't offered again
  PATH=$PWD/bin:$PATH clod __complete home rm vol:vhome '' > out
  has -x work < out
  if grep -qx vol:vhome out; then false; fi
  # home cp and mv: a home, then a new one, which only a path completes
  PATH=$PWD/bin:$PATH clod __complete home cp '' | has -x work
  PATH=$PWD/bin:$PATH clod __complete home mv '' | has -x vol:vhome
  test -z "$(PATH=$PWD/bin:$PATH clod __complete home cp work '')"
  if clod __complete home cp ./w; then false; fi
  if clod __complete home mv work ./w; then false; fi
  PATH=$PWD/bin:$PATH clod __complete workspace rm '' | has -x play
  PATH=$PWD/bin:$PATH clod __complete workspace rm vol : '' | has -x play
  test "$(PATH=$PWD/bin:$PATH clod __complete workspace rm vo)" = vol:play
  test -z "$(PATH=$PWD/bin:$PATH clod __complete workspace rm vol:play '')"
  for sh in bash zsh; do
    [[ $sh == bash ]] || command -v "$sh" >/dev/null || continue
    PATH=$PWD/bin:$PATH "$repo/test/tab-complete.py" "$sh" 'clod -i go+su' 'clod --image=go+su' \
      'clod --home=wo' 'clod -H vol:vh' 'clod --home=vol:vh' 'clod --workspace=vol:pl' \
      'clod -w pro' 'clod --workspace=pro' 'clod claude pro' 'clod image sh' 'clod shared d' \
      'clod home rm vol:vh' 'clod workspace rm pl' 'clod workspace rm vol:pl' \
      'clod workspace rm vo' 'clod home cp wo' 'clod home mv vol:vh' 'clod home rm wo' > out
    sed 's|proj/$|proj|' out | diff - <(printf '%s\n' 'clod -i go+sudo' 'clod --image=go+sudo' \
      'clod --home=work' 'clod -H vol:vhome' 'clod --home=vol:vhome' 'clod --workspace=vol:play' \
      'clod -w proj' 'clod --workspace=proj' 'clod claude proj' 'clod image show' 'clod shared diff' \
      'clod home rm vol:vhome' 'clod workspace rm play' 'clod workspace rm vol:play' \
      'clod workspace rm vol:play' 'clod home cp work' 'clod home mv vol:vhome' 'clod home rm work')
  done
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
# The default home, which a run without a terminal won't create.
mkdir -p "$HOME/.clod/homes/default"
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
