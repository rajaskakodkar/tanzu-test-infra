#!/bin/bash

export dockerfile_path="${1}"
export registry_path="${2}"

source /usr/local/bin/dind.sh

# Check for REGISTRY creds
export REGISTRY_ENABLED=${REGISTRY_ENABLED:-false}
if [[ "${REGISTRY_ENABLED}" == "true" ]]; then
  start_dind
  echo "Registry is enabled, building and pushing image to ${registry_path}"
  export REGISTRY_USERNAME=${REGISTRY_USERNAME:-false}
  export REGISTRY_PASSWORD=${REGISTRY_PASSWORD:-false}
  export AWS_ACCESS_KEY_ID=$(cat ${AWS_ACCESS_KEY_ID})
  export AWS_SECRET_ACCESS_KEY=$(cat ${AWS_SECRET_ACCESS_KEY})
  # Login into registry
  aws ecr-public get-login-password --region us-east-1 | docker login --username $(cat ${REGISTRY_USERNAME}) --password-stdin public.ecr.aws || { error "Failed to login to ECR"; exit 1; }
  # Build image
  cd "${dockerfile_path}"
  docker build -t "${registry_path}" . || { error "Failed to build image in ${registry_path}"; exit 1; }
  # Push image to registry
  docker tag "${registry_path}":latest "${registry_path}":v$(date +%Y%d%m-$(git log -1 --pretty=%h)) || { error "Failed to tag ${registry_path}:latest"; exit 1; }
  docker push "${registry_path}":v$(date +%Y%d%m-$(git log -1 --pretty=%h)) || { error "Failed to push ${registry_path}:v$(date +%Y%d%m-$(git log -1 --pretty=%h))"; exit 1; }
  # cleanup after job
  if [[ "${DOCKER_IN_DOCKER_ENABLED}" == "true" ]]; then
      echo "Cleaning up after docker in docker."
      printf '=%.0s' {1..80}; echo
      cleanup_dind
      printf '=%.0s' {1..80}; echo
      echo "Done cleaning up after docker in docker."
  fi
fi

