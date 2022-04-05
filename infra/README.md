# Scripts for building PROW POC infra on AWS

Most of this scripting was taken from the TCE project and modified for our use.

`build_prow_infra_on_aws.sh` will build 3 cluster:
- management: prow-mgr - this is the TCE management cluster
- prow service: prow-service - this will run the prow infrastructure and trusted postsubmit jobs
- prow build: prow-build - this will run client repo untrusted presubmit jobs

Each cluster is made up of one control plane node and one worker node - both M5 size.  The clusters have a bastion host. They also have a load balancer which is targeted by kubeconfig for access to the cluster.

TCE package repo has been installed on the service and build clusters in the "tanzu-package-repo-global" namespace.

This repo has two folders: jobs-variable and prow-variable, that contain the source files (with variables) for the /jobs and /prow folders that will be used to deploy Prow.  **Caution** The build script will remove /jobs and /prow and replace them with new versions of yaml WITH variables replace.  Once the prow variables have been applied and the new folders created, the script will push the latest folders to the infra repo.  Auto update of Prow depends on file changes within /prow/cluster.  When making changes to Prow application version, remember to change both files within /prow/cluster **AND** /prow-variable/cluster.

**Note:**
aws-nuke does not work and is commented out.  The PowerUser rights we have in our sandbox AWS accounts do not allow us to use Alias which is required for aws-nuke.

**Note:**
This scripting uses gnu-sed `gsed`.  It will be installed by the install-dependencies script.

## AWS Infra Cluster Build variables
These variables need to be exported to the console for the build script to process.  The AWS_SESSION_TOKEN will expire so a managed account build is only useful for "short" tests or jobs that don't require long running AWS sessions.  Useful for: build cluster --> do tests --> destroy

To get started:
1) specify a directory to place your keys and sensitive data in
2) create or copy files with sensitive data to the above directory
   1) github token
   2) github oauth config
   3) github app cookie
   4) hmac secret
   5) oauth token
   6) GCP bucket service account
3) create an env.txt file with the below export statements and update for your environment and keys.  Copy current cloudgate id/key/token to env.txt
4) copy contents of env.txt to your terminal session to create environment variables in the session
5) run ./build_prow_infra_on_aws.sh to start your build
6) Update your DNS cname with ingress LB address

Once all is deployed and running, the only job that will be configured will be what was originally configured in the job-seed.yaml file.  In order to implement any other jobs, you will need to edit the job yaml (add a comment) and submit that change via a PR for the config-updater to pick it up and update the job-config configmap.

**cloudgate**
```
export AWS_ACCESS_KEY_ID=<access key id>
export AWS_SECRET_ACCESS_KEY=<secret access key>
export AWS_SESSION_TOKEN=<session token if managed account>

```
**cluster variables**
```
export AWS_AMI_ID="ami-"
export AWS_REGION=us-east-1
export AWS_NODE_AZ="us-east-1a"
export AWS_SSH_KEY_NAME="default-aws"

export MGMT_CLUSTER_NAME="prow-mgr"
export MGMT_CLUSTER_PLAN="dev"
export MGMT_CONTROL_PLANE_MACHINE_TYPE="m5.large"
export MGMT_NODE_MACHINE_TYPE="m5.large"

export SERVICE_CLUSTER_NAME="prow-service"
export SERVICE_CLUSTER_PLAN="dev"
export SERVICE_CONTROL_PLANE_MACHINE_TYPE="m5.large"
export SERVICE_NODE_MACHINE_TYPE="m5.large"

export BUILD_CLUSTER_NAME="prow-build"
export BUILD_CLUSTER_PLAN="dev"
export BUILD_CONTROL_PLANE_MACHINE_TYPE="m5.large"
export BUILD_NODE_MACHINE_TYPE="m5.large"
```

**prow app variables**
```
export GITHUB_APP_ID=<github app id>
export GITHUB_ORG="AndyTauber"
export GITHUB_REPO1="andy-infra"
export GITHUB_REPO2="andy-prow"
export MY_EMAIL="atauber@vmware.com"
export JOB_CONFIG_PATH="path-to-jobs/config/prow/job-seed.yaml"
export GCS_BUCKET="andytauber-prow"
export PROW_FQDN="prow.andytauber.info"
export CERT_EMAIL="atauber@vmware.com"
export REGISTRY_USERNAME="AWS"
export REGISTRY_PUSH="public.ecr.aws/<registry address>"
```

**Secrets**
Use the following variables to create the secrets
```
export USE_EXTERNAL_SECRETS=false
export SECRETS_ROLE_ARN="arn:aws:iam::609817409085:role/prow-ecr"
export KUBECONFIG_PATH="path-to/kubeconfig.yaml"
# where is gencred
export K8S_TESTINFRA_PATH="/path-to/prow/kubernetes/test-infra"
export GCS_CREDENTIAL_PATH="/path-to/service-account.json"
export HMAC_TOKEN_PATH="/path-to/hmac-secret"
export GITHUB_TOKEN_PATH="/path-to/andytauber-prow-test.2022-03-10.private-key.pem"
export OAUTH_CONFIG_PATH="/path-to/github-oauth-config"
export COOKIE_PATH="/path-to/cookie.txt"
# is registry password still created and this not used?
export REGISTRY_PASSWORD="test"
```

## Required infra setup
You will need github repos setup, github app, AWS ECR, and GCP bucket for logs.  Also a domain name and ability to create a cname record in dns.

Use: https://github.com/rajaskakodkar/prow-on-tce and https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md to get required infra up and running so you can fill in the environment variables above.  

**Some notes of clarification:**

You need to create a kubeconfig.yaml file with gencred and apply the kubeconfig secret to prow namespace before you create the build cluster.  After creating the build cluster, update the kubeconfig secret once more.  This should be handled within the build_prow_on_aws.sh script.

Once you've created the Github app using the instructions: https://docs.github.com/en/developers/apps/building-github-apps/creating-a-github-app, don't forget to install the app to your org.  This is not spelled out in the documentation.
