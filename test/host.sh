#!/bin/bash
# Host portability checks, with fake Docker responses and native utilities.
# Runs on macOS (including its Bash 3.2) and Linux; no Docker daemon needed.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd -P)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HOME=$work/home
export PATH="$work/bin:$PATH"
while IFS= read -r v; do unset "$v"; done < <(compgen -v CLOD_)
mkdir -p "$work/bin" "$HOME/.clod/images/old" "$HOME/.clod/images/top" "$HOME/.clod/images/keep"
mkdir -p "$HOME/volumes"
: > "$HOME/images"
printf 'FROM scratch\n' > "$HOME/.clod/images/old/Dockerfile"
# shellcheck disable=SC2016 # BASE is expanded by Docker, not the host shell
printf 'ARG BASE=clod\nFROM $BASE\n' > "$HOME/.clod/images/top/Dockerfile"
printf 'FROM scratch\n' > "$HOME/.clod/images/keep/Dockerfile"
cat > "$work/bin/docker" <<'DOCKER'
#!/bin/bash
set -eu
case "$*" in
  'version -f {{.Server.Version}}') echo fake ;;
  'image ls --filter label=clod.hash --format {{.Repository}}:{{.Tag}}')
    cat "$HOME/images" ;;
  'image ls --filter label=clod.hash --format {{.Repository}}')
    sed 's/:.*//' "$HOME/images" ;;
  'image inspect -f {{index .Config.Labels "clod.hash"}} '*)
    echo old-hash ;;
  'image inspect -f {{index .Config.Labels "clod.devcontainer.config"}} '*)
    echo "$HOME/deleted/devcontainer.json" ;;
  'image inspect -f {{index .Config.Labels "clod.devcontainer.workspace"}} '*)
    echo "$HOME/deleted" ;;
  'image inspect -f {{.Id}} '*) echo "id-${@: -1}" ;;
  'ps -aq') echo container ;;
  'inspect -f {{.Image}} container') echo id-clod-keep ;;
  'inspect -f {{range .Mounts}}{{.Source}}{{"\n"}}{{end}} container') ;;
  'ps -aq --filter volume='*)
    [[ ${@: -1} != volume=clod-workspace-busy ]] || echo container ;;
  'volume ls -q --filter name='*)
    prefix=${@: -1}
    for volume in "$HOME/volumes/${prefix#name=}"*; do
      [[ ! -f $volume ]] || basename "$volume"
    done ;;
  'volume inspect '*) test -f "$HOME/volumes/$3" ;;
  'volume create '*) touch "$HOME/volumes/$3"; echo "$3" ;;
  'volume rm '*) rm "$HOME/volumes/$3" ;;
  'rmi '*) echo "Deleted: ${2}" ;;
  'image prune -f --filter label=clod.hash') ;;
  *) echo "unexpected Docker call: $*" | tee -a "$HOME/unexpected-docker" >&2; exit 1 ;;
esac
DOCKER
chmod +x "$work/bin/docker"
cd "$work"

clod() { "$repo/clod" "$@"; }
check() {
  local want=$1 got=0
  shift
  clod "$@" > actual 2> errors || got=$?
  if [[ $got != "$want" ]]; then
    echo "clod $*: wanted exit $want, got $got" >&2
    cat actual errors >&2
    exit 1
  fi
  if [[ $want == 0 && -s errors ]]; then cat errors >&2; exit 1; fi
}
# has PATTERN [FILE]: FILE (default actual) has a line matching PATTERN.
has() {
  if ! grep -E "$1" "${2:-actual}" > /dev/null; then
    echo "missing output matching: $1" >&2
    cat "${2:-actual}" >&2
    exit 1
  fi
}
# Fails on any line of actual wider than 80 columns, naming them.
fits() {
  local wide
  wide=$(awk 'length > 80' actual)
  if [[ -n $wide ]]; then
    echo "lines over 80 columns:" >&2
    echo "$wide" >&2
    exit 1
  fi
}
completes() { clod __complete "$@" | cut -f1 > actual; }

# Help and argument handling need no Docker, on every command's help page.
for command in help env default install uninstall update completion claude codex opencode bash zsh \
  image 'image show' 'image new' 'image edit' 'image diff' 'image rm' \
  'image build' 'image rebuild' 'image clean' 'image prune' \
  home 'home new' 'home cp' 'home mv' 'home rm' workspace 'workspace rm' \
  shared 'shared new' 'shared edit' 'shared diff'; do
  # shellcheck disable=SC2086 # split each command into its noun and verb
  check 0 help $command
  has '^usage: clod '
done
check 0 --version
has '^clod '
check 0 -h
has '^Options go before the command, or after it up to --, except after$'
has "^claude, codex, opencode, bash or zsh, whose arguments are the program's$"
has '  env +show the home, workspace, image, ports and variables$'
fits
check 2 --nope
check 2 image prune extra
check 2 image new
check 2 image new -- -invalid
check 2 image nope
check 2 home new a b
check 2 workspace rm
check 2 shared
has 'shared takes a command: new, diff or edit' errors
echo 'PASS help and arguments'

# Settings persist, options override them, and resetting restores defaults.
check 0 default
has '^base +slim '
check 0 default base full
check 0 env
has '^image: +clod:full$'
check 0 default command bash
check 0 default ports 3000:8080
check 0 env -H other -i python
has '^home: +other'
has '^image: +python '
has '^ports: +127\.0\.0\.1:3000 → 8080 '
check 0 default base --reset
check 0 default ports --reset
check 0 default command --reset
check 2 default base invalid
check 2 default command invalid
check 2 default ports invalid
check 2 default unknown
check 0 env -w "$work" -P 6000/udp
has '^ports: +127\.0\.0\.1:6000 → 6000/udp$'
echo 'PASS settings and environment'

# Real filesystem operations: custom variants, editing, diffs and shared config.
check 0 image new mine
test -f "$HOME/.clod/images/mine/Dockerfile"
check 1 image new mine
check 2 image new Invalid
check 0 image new python
check 0 image diff python
echo '# changed' >> "$HOME/.clod/images/python/Dockerfile"
check 1 image diff python
has '^\+# changed$'
check 0 image show mine
has 'mine'
export VISUAL=echo
check 0 image edit mine
has '/images/mine/Dockerfile$'
check 2 image edit mine ../config
check 1 image edit clod
check 1 shared diff
check 0 shared new
test -f "$HOME/.clod/shared/settings.json"
check 0 shared diff
# with no instructions file there yet, shared edit opens AGENTS.md
check 0 shared edit
has '/shared/AGENTS.md$'
# a CLAUDE.md kept from before AGENTS.md opens while it is all the
# instructions there, AGENTS.md takes over once it exists, and naming a file
# still opens that one
echo '# legacy' > "$HOME/.clod/shared/CLAUDE.md"
check 0 shared edit
has '/shared/CLAUDE.md$'
echo '# mine' > "$HOME/.clod/shared/AGENTS.md"
check 0 shared edit
has '/shared/AGENTS.md$'
check 0 shared edit CLAUDE.md
has '/shared/CLAUDE.md$'
check 0 shared edit settings.json
has '/shared/settings.json$'
# shared new names either name of instructions file that describes the
# container; the warnings go to stdout with the report
cat >> "$HOME/.clod/shared/CLAUDE.md" <<'MARK'
Started by running in a disposable container (`docker run --rm`) started by the user's `clod` launcher
MARK
out=$(clod shared new)
[[ $out == *'shared/CLAUDE.md describes the container'* ]] || {
  echo "missing CLAUDE.md warning: $out" >&2
  exit 1
}
[[ $out != *'shared/AGENTS.md describes the container'* ]] || {
  echo "unexpected AGENTS.md warning: $out" >&2
  exit 1
}
cat >> "$HOME/.clod/shared/AGENTS.md" <<'MARK'
Started by running in a disposable container (`docker run --rm`) started by the user's `clod` launcher
MARK
out=$(clod shared new)
[[ $out == *'shared/AGENTS.md describes the container'* ]] || {
  echo "missing AGENTS.md warning: $out" >&2
  exit 1
}
check 2 shared edit ../config
echo '# changed' >> "$HOME/.clod/shared/settings.json"
check 1 shared diff
has '^\+# changed$'
unset VISUAL
# A variant's ARG BASE can name an image as -i does: a combination, or a
# devcontainer by its path, relative to the variant's directory. image new
# writes a devcontainer's path in full. Such a variant goes first in a
# combination, and the workspace's devcontainer can't be a variant's base.
mkdir -p "$work/proj/.devcontainer"
echo '{}' > "$work/proj/.devcontainer/devcontainer.json"
check 0 image new pair top+python
has 'built on top\+python$'
has '^ARG BASE=top\+python$' "$HOME/.clod/images/pair/Dockerfile"
if [[ $(head -1 "$HOME/.clod/images/pair/Dockerfile") != '# check=skip=InvalidDefaultArgInFrom' ]]; then
  echo "image new's starter doesn't start with the check directive" >&2
  exit 1
fi
check 0 image new short devcontainer:proj/+top
has '^ARG BASE=devcontainer:/.*/proj/\+top$' "$HOME/.clod/images/short/Dockerfile"
check 1 image new nope devcontainer
has 'by its path' errors
check 1 image new nope devcontainer:proj
check 1 image new nope 'devcontainer:my proj/'
has 'invalid image name' errors
test ! -e "$HOME/.clod/images/nope"
check 1 image new nope devcontainer:missing/
has 'no devcontainer at' errors
check 0 env -i short
has '^image: +short '
# the devcontainer it's built on is the run's, so env doesn't offer it
(cd proj && clod env -i short) > actual
if grep -q '^devcontainer:' actual; then
  echo 'env offers the devcontainer the run is built on' >&2
  exit 1
fi
check 0 image new dotted top.python
has '^ARG BASE=top\+python$' "$HOME/.clod/images/dotted/Dockerfile"
# a single name stays a Docker name, and a variant on a base still goes on top
mkdir "$HOME/.clod/images/hub" "$HOME/.clod/images/full"
# shellcheck disable=SC2016 # BASE is expanded by Docker, not the host shell
printf 'ARG BASE=python\nFROM $BASE\n' > "$HOME/.clod/images/hub/Dockerfile"
# shellcheck disable=SC2016
printf 'ARG BASE=clod:full\nFROM $BASE\n' > "$HOME/.clod/images/full/Dockerfile"
check 0 image show hub
if grep -q '^python ' actual; then
  echo 'ARG BASE=python resolved to the python variant' >&2
  exit 1
fi
check 0 env -i top+full
has '^image: +top\+full '
rm -rf "$HOME/.clod/images/hub" "$HOME/.clod/images/full" "$HOME/.clod/images/dotted"
check 0 env -i pair+short
has "variant short can't go on top of another: it is built on devcontainer:"
check 1 image build pair+short
has "variant short can't go on top" errors
completes -i 'top+'
if grep -qE 'short|pair' actual; then
  echo 'completion offers a variant with a base of its own on top' >&2
  exit 1
fi
mkdir "$HOME/.clod/images/rel" "$HOME/.clod/images/ws"
# shellcheck disable=SC2016 # BASE is expanded by Docker, not the host shell
printf 'ARG BASE=devcontainer:../../../../proj/\nFROM $BASE\n' > "$HOME/.clod/images/rel/Dockerfile"
# shellcheck disable=SC2016
printf 'ARG BASE=devcontainer\nFROM $BASE\n' > "$HOME/.clod/images/ws/Dockerfile"
check 0 image show rel
has '^rel +[a-z]+ +devcontainer:\.\./\.\./\.\./\.\./proj/ '
has '^devcontainer +[a-z]+ +- +.*/proj/\.devcontainer/devcontainer\.json'
check 0 env -i ws
has 'whichever workspace clod runs in'
check 1 image build ws
rm -rf "$HOME/.clod/images/pair" "$HOME/.clod/images/short" "$HOME/.clod/images/rel" "$HOME/.clod/images/ws"
echo 'PASS image files and shared config'

# Homes use real directories; Docker volume state is held by the fake CLI.
check 0 home new made
printf 'login\n' > "$HOME/.clod/homes/made/credential"
check 1 home new made
check 0 home mv made moved
test ! -d "$HOME/.clod/homes/made"
test "$(cat "$HOME/.clod/homes/moved/credential")" = login
check 0 home new vol:extra
check 0 home
has '^  moved '
has '^  vol:extra '
check 1 home rm moved < /dev/null
test -d "$HOME/.clod/homes/moved"
check 0 home rm moved vol:extra --force
test ! -d "$HOME/.clod/homes/moved"
test ! -f "$HOME/volumes/clod-home-extra"
check 1 home new "$HOME"
check 0 workspace
has 'no volume workspaces'
touch "$HOME/volumes/clod-workspace-one" "$HOME/volumes/clod-workspace-busy"
check 0 -w vol:one workspace
has '^\* vol:one '
has '^  vol:busy +in use$'
check 1 workspace rm one missing --force
test -f "$HOME/volumes/clod-workspace-one"
check 1 workspace rm busy --force
test -f "$HOME/volumes/clod-workspace-busy"
check 0 workspace rm one --force
test ! -f "$HOME/volumes/clod-workspace-one"
echo 'PASS homes and workspaces'

# Completion generation, candidates and installation through a real symlink.
check 0 completion
/bin/bash -n actual
completes image ''
has '^prune$'
completes image edit ''
has '^mine$'
completes default base ''
has '^full$'
completes shared edit ''
has '^settings.json$'
check 0 install "$HOME/.local/bin"
test -L "$HOME/.local/bin/clod"
"$HOME/.local/bin/clod" --version > actual
has '^clod '
echo 'PASS completion and install'

# Bases, variants, combinations and orphaned devcontainers are eligible.
# Other repositories and custom tags must stay out of the candidate list.
cat > "$HOME/images" <<'IMAGES'
clod:latest
clod:full
clod-old:latest
clod-old.top:latest
clod-keep:latest
clod-unknown:latest
clod-devcontainer-0123456789ab:latest
other:latest
clod-old:custom
<none>:<none>
IMAGES
check 0 image
has '^  old\+top +stale '
has '^  keep +stale, in use '
# A CLOD_IMAGE clod can't run is a warning where it lists, and an error where
# it needs the image.
export CLOD_IMAGE=python+nosuch
clod image > actual 2> errors
has "^clod: no variant named 'nosuch'" errors
has '^  keep '
clod env > actual 2> errors
has "^image: +python\+nosuch \(no variant named 'nosuch'"
for command in bash 'image build' 'image clean' 'image edit'; do
  # shellcheck disable=SC2086 # split each command into its noun and verb
  check 1 $command
  has "^clod: no variant named 'nosuch'" errors
done
export CLOD_IMAGE='+python'
clod env > actual 2> errors
has "^image: +\+python \(invalid CLOD_IMAGE"
unset CLOD_IMAGE
check 0 image clean old
has '^removed old$'
check 1 image clean keep
check 0 image rm mine --force
test ! -d "$HOME/.clod/images/mine"
"$repo/clod" image prune > actual 2> errors
test ! -s errors || { cat errors >&2; exit 1; }
cat > expected <<'EXPECTED'
removed old+top
removed old
removed devcontainer
removed clod:full
removed clod
kept keep: a container uses it (docker ps -a lists them)
EXPECTED
diff -u expected actual

# An empty candidate list is a successful no-op, without grep diagnostics.
: > "$HOME/images"
"$repo/clod" image prune > actual 2> errors
test ! -s errors || { cat errors >&2; exit 1; }
printf 'clod: no stale images\n' > expected
diff -u expected actual
test ! -s "$HOME/unexpected-docker" || { cat "$HOME/unexpected-docker" >&2; exit 1; }
echo 'PASS image listing, clean, rm and prune'
echo 'Host portability checks passed'
