#!/bin/sh

set -eux

main() {
  local dockerfile_path
  dockerfile_path="${1}"

  # Start Docker
  dockerd-entrypoint.sh &

  # Docker takes a few seconds to initialize
  while (! docker stats --no-stream > /dev/null 2>&1 ); do
    sleep 1
  done

  # Build docker image...
  cd "${dockerfile_path}"
  docker build .
  local docker_build_exitcode
  docker_build_exitcode="${?}"

  # Stop Docker background job
  kill %1

  # Exit with exit code of docker build
  exit ${docker_build_exitcode}
}

main ${@}
