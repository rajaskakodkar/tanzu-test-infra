#!/bin/bash

# util function
function error {
    printf '\E[31m'; echo "$@"; printf '\E[0m'
}

# runs custom docker data root cleanup binary and debugs remaining resources
function cleanup_dind {
    if [[ "${DOCKER_IN_DOCKER_ENABLED:-false}" == "true" ]]; then
        echo "Cleaning up after docker"
        docker ps -aq | xargs -r docker rm -f || true
        service docker stop || true
    fi
}

# Check for DOCKER_IN_DOCKER_ENABLED
function start_dind {
    export DOCKER_IN_DOCKER_ENABLED=${DOCKER_IN_DOCKER_ENABLED:-false}
    if [[ "${DOCKER_IN_DOCKER_ENABLED}" == "true" ]]; then
        echo "Docker in Docker enabled, initializing..."
        printf '=%.0s' {1..80}; echo
        # If we have opted in to docker in docker, start the docker daemon,
        service docker start
        # the service can be started but the docker socket not ready, wait for ready
        WAIT_N=0
        MAX_WAIT=5
        while true; do
            # docker ps -q should only work if the daemon is ready
            docker ps -q > /dev/null 2>&1 && break
            if [[ ${WAIT_N} -lt ${MAX_WAIT} ]]; then
                WAIT_N=$((WAIT_N+1))
                echo "Waiting for docker to be ready, sleeping for ${WAIT_N} seconds."
                sleep ${WAIT_N}
            else
                error "Reached maximum attempts, not waiting any longer..."
                exit 1
            fi
        done
        printf '=%.0s' {1..80}; echo
        echo "Done setting up docker in docker."
    fi
}

