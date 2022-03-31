#!/bin/sh

AWS_REGION="us-east-2"
ECR_REGISTRY_TOKEN="t0q8k6g2"

ARTIFACTS="${ARTIFACTS:-${PWD}/_artifacts}"
mkdir -p "$ARTIFACTS/logs/"

# list of image repositories to sync in internal ecr
declare -a images=(
		   "another-test"
		   "hook"
		   "sinker"
		   "deck"
		   "horologium"
		   "status-reconciler"
		   "ghproxy"
		   "prow-controller-manager"
		   "crier"
		   "checkconfig"
		   "clonerefs"
		   "initupload"
		   "entrypoint"
		   "sidecar"
		   "kubernetes-external-secrets"
                   "boskos" 
		   "aws-janitor-boskos"
		   "cleaner"
		   "reaper"
		   "summarizer"
		   "updater"
	   )

# Logging to the ECR registry
echo "[INFO] Logging to ECR registry ..."
printf '~%.0s' {1..80}; echo
aws ecr-public get-login-password --region ${AWS_REGION} | skopeo login --username AWS --password-stdin public.ecr.aws

# Create ecr-public repostories
echo "[INFO] Checking ECR Repository ..."
printf '~%.0s' {1..80}; echo
for repository_name in "${images[@]}"
do
	aws ecr-public describe-repositories --repository-names ${repository_name} --region ${AWS_REGION} >> $ARTIFACTS/logs/aws-ecr-public.log || aws ecr-public create-repository --repository-name ${repository_name} --region ${AWS_REGION} >> $ARTIFACTS/logs/aws-ecr-public.log
done

# Sync the upstream/third-party image tags with internal ecr images

echo "[INFO] Starting syncing images to ECR..."
printf '~%.0s' {1..80}; echo
skopeo sync --src yaml source-images.yaml --dest docker public.ecr.aws/${ECR_REGISTRY_TOKEN}/ --keep-going
