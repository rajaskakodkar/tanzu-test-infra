

#!/bin/bash

# Copyright 2021 VMware Tanzu Community Edition contributors. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

function aws-nuke-tear-down {
	echo "$1"
	envsubst < "${REPO_PATH}"/infra/aws/utils/nuke-config-template.yml > "${REPO_PATH}"/infra/aws/utils/nuke-config.yml
	aws-nuke -c "${REPO_PATH}"/infra/aws/utils/nuke-config.yml --access-key-id "$AWS_ACCESS_KEY_ID" --secret-access-key "$AWS_SECRET_ACCESS_KEY" --force --no-dry-run || { error "$2 CLUSTER DELETION FAILED!!!"; rm -rf "${REPO_PATH}"/infra/aws/utils/nuke-config.yml; exit 1; }
	rm -rf "${REPO_PATH}"/infra/aws/utils/nuke-config.yml
	echo "$2 DELETED using aws-nuke!"
}
