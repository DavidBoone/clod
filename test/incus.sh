#!/bin/bash
# Runs test/run.sh in an incus container with its own Docker, from the
# checkout as it is on disk (tracked files, and untracked ones git doesn't
# ignore). The container stays between runs, so Docker's images and build
# cache make later runs warm; 'new' makes it again, for a cold run.
#
#   test/incus.sh run [TEST|GROUP...]   run them, or every test (makes the container if needed)
#   test/incus.sh new                   make the container, replacing it
#   test/incus.sh rm                    delete the container
#
# The incus client's default remote runs the container, or the one named in
# CLOD_TEST_INCUS (default clod-test, or REMOTE:NAME). Its profile
# CLOD_TEST_PROFILE (default docker) lets Docker run inside: security.nesting
# and the mknod and setxattr syscall intercepts, with cloud-init installing
# docker.io.

container=${CLOD_TEST_INCUS:-clod-test}
profile=${CLOD_TEST_PROFILE:-docker}
image=images:ubuntu/24.04/cloud
# What the GitHub runners have that run.sh uses, beyond the profile's docker.io.
packages='git shellcheck direnv zsh bash-completion python3 jq docker-buildx'
repo=$(cd "$(dirname "$0")/.." && pwd -P)

usage() {
  sed -n '/^#   test/s/^# *//p' "$0"
}

# Runs a command in the container, retrying when the client fails to reach it.
# Only for commands that are safe to run twice.
cexec() {
  local i
  for i in 1 2 3 4 5; do
    incus exec "$container" -- "$@" </dev/null && return
    (( i < 5 )) && sleep 5
  done
  return 1
}

cmd_new() {
  echo "test/incus.sh: making $container"
  incus delete -f "$container" >/dev/null 2>&1
  incus launch "$image" "$container" -p default -p "$profile" </dev/null >/dev/null || return 1
  cexec cloud-init status --wait >/dev/null || return 1
  cexec bash -ec "
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -yq $packages >/dev/null
    id runner >/dev/null 2>&1 || useradd -m -s /bin/bash -G docker runner
  "
}

cmd_rm() {
  incus delete -f "$container"
}

# The result lines in run.sh's output.
results='^(ok   |FAIL |     variant builds|all [0-9]+ passed|[0-9]+ of [0-9]+ failed)| failed at line '

cmd_run() {
  local args='' shown=0 out status
  incus info "$container" >/dev/null 2>&1 || cmd_new || return 1
  if incus exec "$container" -- pgrep -u runner -f test/run.sh </dev/null >/dev/null; then
    echo "test/incus.sh: a run is already going in $container" >&2
    return 1
  fi
  (cd "$repo" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -czf -) |
    incus exec "$container" -- su - runner -c 'rm -rf clod out status && mkdir clod && tar -xzf - -C clod' ||
    return 1
  (( $# )) && printf -v args ' %q' "$@"
  # The run is detached, so losing the connection doesn't stop it; ~/status
  # holds its exit status once it's done.
  incus exec "$container" -- su - runner -c "cd clod && setsid nohup bash -c 'test/run.sh --yes$args > ~/out 2>&1; echo \$? > ~/status' </dev/null >/dev/null 2>&1 &" </dev/null ||
    return 1
  while :; do
    sleep 10
    # The status first: once it's there, the output is complete.
    status=$(incus exec "$container" -- cat /home/runner/status </dev/null 2>/dev/null) || status=''
    out=$(incus exec "$container" -- grep -aE "$results" /home/runner/out </dev/null 2>/dev/null) || {
      [[ -z $status ]] && continue
    }
    if [[ -n $out ]]; then
      printf '%s\n' "$out" | tail -n +$((shown + 1))
      shown=$(printf '%s\n' "$out" | wc -l)
    fi
    [[ -n $status ]] && break
  done
  if (( status )); then
    cexec tail -n 5 /home/runner/out
    echo "(the output is in $container:/home/runner/out; 'incus exec $container -- su - runner' gets a shell there)"
  fi
  return "$status"
}

case $1 in
  run) shift; cmd_run "$@" ;;
  new|rm)
    if (( $# > 1 )); then
      echo "test/incus.sh: $1 takes no arguments" >&2; usage >&2; exit 2
    fi
    "cmd_$1" ;;
  -h|--help|help) usage ;;
  *) echo "test/incus.sh: unknown command '${1-}'" >&2; usage >&2; exit 2 ;;
esac
