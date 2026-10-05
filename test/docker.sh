#!/bin/bash
# Runs test/run.sh in a container with its own Docker inside, on whichever
# Docker the docker CLI uses (its context, or DOCKER_HOST), from the checkout
# as it is on disk (tracked files, and untracked ones git doesn't ignore). The
# suite builds, replaces and prunes clod images only in that inner Docker, so
# the outer one's images and containers are left alone. The inner Docker
# keeps its images and build cache in a volume, so later runs are warm; 'new'
# makes it all again, for a cold run.
#
#   test/docker.sh run [TEST|GROUP...]   run them, or every test (makes the container if needed)
#   test/docker.sh new                   make the container and its volume, replacing them
#   test/docker.sh rm                    delete the container, its volume and its image
#
# The container (CLOD_TEST_DOCKER, default clod-test) runs privileged, as an
# inner dockerd must, which is root on the outer Docker's host. Its volume and
# image are named after it: NAME-docker and NAME-runner.

name=${CLOD_TEST_DOCKER:-clod-test}
volume=$name-docker
image=$name-runner
repo=$(cd "$(dirname "$0")/.." && pwd -P)

# Ubuntu, as on the GitHub runners, with what they have that run.sh uses.
read -r -d '' dockerfile <<'EOF' || true
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -yq --no-install-recommends \
      docker.io docker-buildx iptables ca-certificates curl git shellcheck direnv zsh bash-completion \
      python3 jq \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m -s /bin/bash -G docker runner
# The classic image store: with containerd's, every build also has containerd
# unpack its layers, and the builds take about a third longer.
RUN mkdir -p /etc/docker && echo '{"features": {"containerd-snapshotter": false}}' > /etc/docker/daemon.json
CMD ["dockerd"]
EOF

usage() {
  sed -n '/^#   test/s/^# *//p' "$0"
}

# Starts the container, making it and its image if needed, and waits for its
# Docker. --init reaps the processes the tests leave to PID 1, which dockerd
# doesn't.
start() {
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    printf '%s\n' "$dockerfile" | docker build -q --pull -t "$image" - >/dev/null || return 1
  fi
  if ! docker container inspect "$name" >/dev/null 2>&1; then
    docker run -d --init --privileged --name "$name" -v "$volume:/var/lib/docker" "$image" >/dev/null ||
      return 1
  fi
  docker start "$name" >/dev/null || return 1
  for _ in $(seq 30); do
    docker exec "$name" docker info >/dev/null 2>&1 && return 0
    sleep 1
  done
  echo "test/docker.sh: the Docker in $name didn't start ('docker logs $name' says why)" >&2
  return 1
}

cmd_rm() {
  docker rm -f "$name" >/dev/null 2>&1
  docker volume rm -f "$volume" >/dev/null
  docker image rm -f "$image" >/dev/null 2>&1
  return 0
}

cmd_new() {
  echo "test/docker.sh: making $name"
  cmd_rm && start
}

# The result lines in run.sh's output.
results='^(ok   |FAIL |     variant builds|all [0-9]+ passed|[0-9]+ of [0-9]+ failed)| failed at line '

cmd_run() {
  local args='' status
  start || return 1
  if docker exec "$name" pgrep -u runner -f test/run.sh >/dev/null; then
    echo "test/docker.sh: a run is already going in $name" >&2
    return 1
  fi
  (cd "$repo" && git ls-files -z --cached --others --exclude-standard | tar --null -T - -czf -) |
    docker exec -i -u runner "$name" bash -c 'rm -rf ~/clod ~/out && mkdir ~/clod && tar -xzf - -C ~/clod' ||
    return 1
  (( $# )) && printf -v args ' %q' "$@"
  docker exec -u runner -w /home/runner/clod "$name" \
    bash -c "set -o pipefail; test/run.sh --yes$args 2>&1 | tee ~/out" |
    grep --line-buffered -aE "$results"
  status=${PIPESTATUS[0]}
  if (( status )); then
    docker exec "$name" tail -n 5 /home/runner/out
    echo "(the output is in $name:/home/runner/out; 'docker exec -it -u runner $name bash' gets a shell there)"
  fi
  return "$status"
}

case $1 in
  run) shift; cmd_run "$@" ;;
  new|rm)
    if (( $# > 1 )); then
      echo "test/docker.sh: $1 takes no arguments" >&2; usage >&2; exit 2
    fi
    "cmd_$1" ;;
  -h|--help|help) usage ;;
  *) echo "test/docker.sh: unknown command '${1-}'" >&2; usage >&2; exit 2 ;;
esac
