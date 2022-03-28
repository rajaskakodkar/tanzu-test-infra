#!/bin/bash

source /usr/local/bin/dind.sh

start_dind

github_org="${1}"
github_repo="${2}"
command="${@:3}"

git clone "https://github.com/${github_org}/${github_repo}"
cd "${github_repo}"
eval "${command}"

if [ $? -eq 0 ]; then
    cleanup_dind
    exit 0
else
    echo "Job failed...."
    cleanup_dind
    exit 1
fi