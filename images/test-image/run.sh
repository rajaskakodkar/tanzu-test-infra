#!/bin/bash

source /usr/local/bin/dind.sh

start_dind

github_org="${1}"
github_repo="${2}"
command="${@:3}"

git clone "https://github.com/${github_org}/${github_repo}"
cd "${github_repo}"
eval "${command}" || { cleanup_dind ; exit 1; }