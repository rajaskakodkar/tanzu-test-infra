#!/usr/bin/env bash

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script builds the Prow infrastructure using GKE Autopilot clusters
# Note: This is WIP and supports only Linux(Debian) and MacOS

# Please view the README.md for list of environment variables that need to be set

set -o errexit
set -o nounset
set -o pipefail

BUILD_OS=$(uname -s)
export BUILD_OS
BUILD_ARCH=$(uname -m)
export BUILD_ARCH

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
REPO_PATH="$(git rev-parse --show-toplevel)"

function create_service_cluster {
    echo "Creating service cluster..."
    gcloud container --project "${PROJECT}" clusters create-auto "prow-service" --region "${REGION}" \
      --release-channel "regular" --enable-private-nodes --enable-master-authorized-networks \
      --master-authorized-networks "${HOME_NET}" --network "projects/"${PROJECT}"/global/networks/default" \
      --subnetwork "projects/"${PROJECT}"/regions/"${REGION}"/subnetworks/default" --cluster-ipv4-cidr "/17" \
      --services-ipv4-cidr "/22" || {
        error "SERVICE CLUSTER CREATION FAILED!"
        exit 1
    }
    gcloud container clusters get-credentials prow-service --region="${REGION}"
    kubectl config use-context "gke"_"${PROJECT}"_"${REGION}"_prow-service || {
        error "CONTEXT SWITCH TO PROW SERVICE CLUSTER FAILED!"
        exit 1
    }
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
        error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
        exit 1
    }
}

function create_build_cluster {
  echo "Creating build cluster..."
  gcloud container --project "${PROJECT}" clusters create-auto "prow-build" --region "${REGION}" \
    --release-channel "regular" --enable-private-nodes --enable-master-authorized-networks \
    --master-authorized-networks "${HOME_NET}" --network "projects/"${PROJECT}"/global/networks/default" \
    --subnetwork "projects/"${PROJECT}"/regions/"${REGION}"/subnetworks/default" --cluster-ipv4-cidr "/17" \
    --services-ipv4-cidr "/22" || {
      error "BUILD CLUSTER CREATION FAILED!"
      exit 1
  }
  gcloud container clusters get-credentials prow-build --region="${REGION}"
  kubectl config use-context "gke"_"${PROJECT}"_"${REGION}"_prow-service || {
      error "CONTEXT SWITCH TO PROW BUILD CLUSTER FAILED!"
      exit 1
  }
  kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
      error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
      exit 1
  }
}

function replace_prow_variables {
    echo "Replacing prow variables..."

    # create new /prow and /job folders
    rm -rf "${REPO_PATH}"/config/prow
    rm -rf "${REPO_PATH}"/config/jobs
    cp -r "${REPO_PATH}"/infra/gcp/configs/prow-variable "${REPO_PATH}"/config/prow
    cp -r "${REPO_PATH}"/infra/gcp/configs/jobs-variable "${REPO_PATH}"/config/jobs

    # replace variables for core prow
    gsed -i -e "s/GCS_BUCKET/${GCS_BUCKET}/g" "${REPO_PATH}"/config/prow/cluster/tide_deployment.yaml;
    gsed -i -e "s/GCS_BUCKET/${GCS_BUCKET}/g" "${REPO_PATH}"/config/prow/cluster/statusreconciler_deployment.yaml;
    gsed -i -e "s/PROW_FQDN/${PROW_FQDN}/g" "${REPO_PATH}"/config/prow/config.yaml;
    gsed -i -e "s/GCS_BUCKET/${GCS_BUCKET}/g" "${REPO_PATH}"/config/prow/config.yaml;
    gsed -i -e "s/GITHUB_ORG/${GITHUB_ORG}/g" "${REPO_PATH}"/config/prow/config.yaml;
    gsed -i -e "s/GITHUB_ORG/${GITHUB_ORG}/g" "${REPO_PATH}"/config/prow/plugins.yaml;
    gsed -i -e "s/GITHUB_REPO1/${GITHUB_REPO1}/g" "${REPO_PATH}"/config/prow/plugins.yaml;
    gsed -i -e "s/GITHUB_REPO2/${GITHUB_REPO2}/g" "${REPO_PATH}"/config/prow/plugins.yaml;
    gsed -i -e "s/GITHUB_ORG/${GITHUB_ORG}/g" "${REPO_PATH}"/config/prow/job-seed.yaml;
    gsed -i -e "s/GITHUB_REPO1/${GITHUB_REPO1}/g" "${REPO_PATH}"/config/prow/job-seed.yaml;
    gsed -i -e "s/STATIC_IP_NAME/${STATIC_IP_NAME}/g" "${REPO_PATH}"/config/prow/cluster/ingress.yaml;
    gsed -i -e "s/PROW_FQDN/${PROW_FQDN}/g" "${REPO_PATH}"/config/prow/cluster/ingress.yaml;
    gsed -i -e "s/PROW_FQDN/${PROW_FQDN}/g" "${REPO_PATH}"/config/prow/cluster/managed-cert.yaml;

    # recurse through all jobs and replace variables
    if [[ $BUILD_OS == "Darwin" ]]; then
      egrep -rl 'GITHUB_ORG' "${REPO_PATH}"/config/jobs | xargs -I@ gsed -i -e "s/GITHUB_ORG/${GITHUB_ORG}/g" @
      egrep -rl 'GITHUB_REPO1' "${REPO_PATH}"/config/jobs | xargs -I@ gsed -i -e "s/GITHUB_REPO1/${GITHUB_REPO1}/g" @
      egrep -rl 'GITHUB_REPO2' "${REPO_PATH}"/config/jobs | xargs -I@ gsed -i -e "s/GITHUB_REPO2/${GITHUB_REPO2}/g" @
      egrep -rl 'REGISTRY_PUSH' "${REPO_PATH}"/config/jobs | xargs -I@ gsed -i -e "s/REGISTRY_PATH/${REGISTRY_PATH}/g" @
    elif [[ $BUILD_OS == "Linux" ]]; then
      grep -rl 'GITHUB_ORG' "${REPO_PATH}"/config/jobs | xargs sed -i "s/GITHUB_ORG/${GITHUB_ORG}/g"
      grep -rl 'GITHUB_REPO1' "${REPO_PATH}"/config/jobs | xargs sed -i "s/GITHUB_REPO1/${GITHUB_REPO1}/g"
      grep -rl 'GITHUB_REPO2' "${REPO_PATH}"/config/jobs | xargs sed -i "s/GITHUB_REPO2/${GITHUB_REPO2}/g"
      grep -rl 'REGISTRY_PUSH' "${REPO_PATH}"/config/jobs | xargs sed -i "s/REGISTRY_PUSH/${REGISTRY_PUSH}/g"
    fi

}

function install_prow_on_service_cluster {
    echo "Installing Prow on service cluster..."
    # Set service cluster variables
    echo "Setting SERVICE CLUSTER NAME to ${SERVICE_CLUSTER_NAME}..."
    export CLUSTER_NAME="${SERVICE_CLUSTER_NAME}"
    tanzu cluster kubeconfig get "${SERVICE_CLUSTER_NAME}" --admin
    kubectl config use-context "${SERVICE_CLUSTER_NAME}"-admin@"${SERVICE_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
        exit 1
    }

    # create initial kubeconfig file
    echo "Create initial kubeconfig file..."
    rm -f "${KUBECONFIG_PATH}"
    cd "${K8S_TESTINFRA_PATH}"
    export KUBECONFIG="~/.kube/config.int"

    # load internal kubeconfig into file
    gcloud container clusters get-credentials prow-service --region=us-west1 --internal-ip
    export KUBECONFIG=""

    go run ./gencred --context="${SERVICE_CLUSTER_NAME}" --name=prow-service-trusted --output="${KUBECONFIG_PATH}"
    go run ./gencred --context="${SERVICE_CLUSTER_NAME}" --name=default --output="${KUBECONFIG_PATH}"
    go run ./gencred --context="${BUILD_CLUSTER_NAME}" --name=prow-gke-build --output="${KUBECONFIG_PATH}"

    # change to internal ip here

    cd "${REPO_PATH}"/config/prow


### Need code here to swap out the internal IP Address  172.16.56.178

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole cluster-admin --user $(gcloud config get-value account) || {
        error "CLUSTERROLEBINDING FAILED"
        exit 1
    }

    # create kubeconfig secret
    kubectl -n prow create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"

    # create configmaps
    echo "Creating configmaps..."
    kubectl create configmap plugins --from-file=plugins.yaml="${REPO_PATH}"/config/prow/plugins.yaml --dry-run=client -oyaml | kubectl apply -f - -n prow
    kubectl create configmap config --from-file=config.yaml="${REPO_PATH}"/config/prow/config.yaml --dry-run=client -oyaml | kubectl apply -f - -n prow
    kubectl create configmap job-config --from-file=${JOB_CONFIG_PATH} --dry-run=client -oyaml | kubectl apply -f - -n prow

    # CRDs
    kubectl apply --server-side=true -f https://raw.githubusercontent.com/kubernetes/test-infra/master/config/prow/cluster/prowjob-crd/prowjob_customresourcedefinition.yaml

    # apply prow components
    kubectl apply -f "${REPO_PATH}"/config/prow/cluster/

    # wait for and display LB fqdn
    echo "Getting the ingress load balancer hostname..."
    INGRESS_HOSTNAME=""
    while [ -z $INGRESS_HOSTNAME ]; do
      echo "Waiting for end point..."
      INGRESS_HOSTNAME=$(kubectl -n prow get ingress prow --output="jsonpath={.status.loadBalancer.ingress[0].hostname}")
      [ -z "$INGRESS_HOSTNAME" ] && sleep 10
    done
    echo "The ingress load balancer hostname is: ${INGRESS_HOSTNAME}..."
    echo "Please update your DNS CNAME to this address."
}

function install_prow_on_build_cluster {
    echo "Installing Prow on build cluster..."
    # Set build cluster variables
    echo "Setting BUILD CLUSTER NAME to ${BUILD_CLUSTER_NAME}..."
    tanzu cluster kubeconfig get "${BUILD_CLUSTER_NAME}" --admin
    kubectl config use-context "${BUILD_CLUSTER_NAME}"-admin@"${BUILD_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO BUILD CLUSTER FAILED!"
        exit 1
    }

    # add build context to kubeconfig file
    echo "Updating the kubeconfig file for Build cluster..."
    cd "${K8S_TESTINFRA_PATH}"
    go run ./gencred --context="${BUILD_CLUSTER_NAME}"-admin@"${BUILD_CLUSTER_NAME}" --name="${BUILD_CLUSTER_NAME}" --output="${KUBECONFIG_PATH}"
    cd "${REPO_PATH}"/config/prow

    kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole cluster-admin --user $(gcloud config get-value account) || {
        error "CLUSTERROLEBINDING FAILED"
        exit 1
    }
    kubectl create ns test-pods || {
        error "CREATE NAMESPACE TEST-PODS FAILED!"
        exit 1
    }

    # CRDs
    kubectl apply --server-side=true -f https://raw.githubusercontent.com/kubernetes/test-infra/master/config/prow/cluster/prowjob-crd/prowjob_customresourcedefinition.yaml

    # create secrets
    kubectl -n test-pods create secret generic gcs-credentials --from-file=${GCS_CREDENTIAL_PATH}

    # update kubeconfig secret on service cluster
    echo "Updating the kubeconfig secret with build cluster context"
    gcloud compute routers create nat-router --network default --region "${REGION}" || {
        error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
        exit 1
    }
    kubectl -n prow delete secret kubeconfig
    kubectl -n prow create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"
}

function install_router_and_bucket {

  echo "Installing NAT ROUTER..."
  gcloud compute routers create nat-router --network default --region "${REGION}" || {
      error "NAT ROUTER CREATE FAILED!"
      exit 1
  }
  gcloud compute routers nats create nat-config \
    --router-region "${REGION}" --router nat-router \
    --nat-all-subnet-ip-ranges --auto-allocate-nat-external-ips || {
      error "NAT ROUTER CONFIG FAILED!"
      exit 1
  }

  echo "CREATING LOG BUCKET..."
  gcloud iam service-accounts create prow-gcs-publisher
  identifier="$(gcloud iam service-accounts list --filter 'name:prow-gcs-publisher' --format 'value(email)')"
  gsutil mb gs://prow-gcs-publisher/
  gsutil iam ch allUsers:objectViewer gs://prow-gcs-publisher
  gsutil iam ch "serviceAccount:${identifier}:objectAdmin" gs://prow-gcs-publisher
  gcloud iam service-accounts keys create --iam-account "${identifier}" service-account.json





}

# Create service, and build clusters
create_service_cluster || exit 1
create_build_cluster || exit 1

# Install packages on service cluster
install_base_packages_on_service_cluster || exit 1

# replace variables in yaml files from infra repo
replace_prow_variables || exit 1

install_prow_on_service_cluster || exit 1
install_prow_on_build_cluster || exit 1

echo "Prow build finished..."
echo "Please push your updated local repo and create a PR to merge changes in..."
