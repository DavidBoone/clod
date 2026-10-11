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
has() {
  if ! grep -E "$1" actual > /dev/null; then
    echo "missing output matching: $1" >&2
    cat actual >&2
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
check 2 --nope
check 2 image prune extra
check 2 image new
check 2 image new -- -invalid
check 2 image nope
check 2 home new a b
check 2 workspace rm
check 2 shared
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
check 0 shared edit settings.json
has '/shared/settings.json$'
check 2 shared edit ../config
echo '# changed' >> "$HOME/.clod/shared/settings.json"
check 1 shared diff
has '^\+# changed$'
unset VISUAL
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
