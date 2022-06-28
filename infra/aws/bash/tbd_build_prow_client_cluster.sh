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

# This script builds a Prow client cluster (build cluster) on AWS
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
# shellcheck source=infra/aws/utils/utils.sh
source "${REPO_PATH}/infra/aws/utils/utils.sh"
# shellcheck source=infra/aws/utils/aws-nuke-tear-down.sh
#source "${REPO_PATH}/infra/aws/utils/aws-nuke-tear-down.sh"
"${REPO_PATH}/infra/aws/utils/install-jq.sh"
"${REPO_PATH}/infra/aws/utils/install-dependencies.sh" || { error "Dependency installation failed!"; exit 1; }

function delete_client_cluster {
    echo "$@"
    export CLUSTER_NAME="${CLIENT_CLUSTER_NAME}"
    tanzu cluster delete "${CLUSTER_NAME}" -y || {
        kubeconfig_cleanup "${CLUSTER_NAME}"
        #aws-nuke-tear-down "MANAGEMENT CLUSTER DELETION FAILED! Deleting the cluster using AWS-NUKE..." "${CLUSTER_NAME}"
    }
}

function create_client_cluster {
    echo "Creating client cluster..."
    # Set service cluster variables
    echo "Setting CLIENT CLUSTER NAME to ${CLIENT_CLUSTER_NAME}..."
    export CLUSTER_NAME="${CLIENT_CLUSTER_NAME}"
    export CLUSTER_PLAN="${CLIENT_CLUSTER_PLAN}"
    export CONTROL_PLANE_MACHINE_TYPE="${CLIENT_CONTROL_PLANE_MACHINE_TYPE}"
    export NODE_MACHINE_TYPE="${CLIENT_NODE_MACHINE_TYPE}"
    tanzu cluster create "${CLUSTER_NAME}" -f "${REPO_PATH}"/infra/aws/configs/client_cluster_config.yaml || {
        error "CLIENT CLUSTER CREATION FAILED!"
        delete_client_cluster "Deleting client cluster"
        exit 1
    }
    tanzu cluster kubeconfig get "${CLIENT_CLUSTER_NAME}" --admin
    kubectl config use-context "${CLIENT_CLUSTER_NAME}"-admin@"${CLIENT_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO CLIENT CLUSTER FAILED!"
        delete_client_cluster "Deleting client cluster"
        exit 1
    }
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
        error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
        delete_client_cluster "Deleting client cluster"
        exit 1
    }
}

function install_prow_on_client_cluster {
    echo "Installing Prow config on client cluster..."
    # Set client cluster variables
    echo "Setting CLUSTER NAME to ${CLIENT_CLUSTER_NAME}..."
    tanzu cluster kubeconfig get "${CLIENT_CLUSTER_NAME}" --admin
    kubectl config use-context "${CLIENT_CLUSTER_NAME}"-admin@"${CLIENT_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO CLIENT CLUSTER FAILED!"
        exit 1
    }

    kubectl create clusterrolebinding cluster-admin-binding-"${USER}" \
    --clusterrole=cluster-admin --user="${USER}" || {
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


    # create kubeconfig for local cluster
    echo "Updating the kubeconfig file for client cluster..."
    mv "${KUBECONFIG_PATH}" "${KUBECONFIG_PATH}".ori
    cd "${K8S_TESTINFRA_PATH}"
    go run ./gencred --context="${CLIENT_CLUSTER_NAME}"-admin@"${CLIENT_CLUSTER_NAME}" --name="${CLIENT_CLUSTER_NAME}" --output="${KUBECONFIG_PATH}"
    cd "${REPO_PATH}"/config/prow

    kubectl -n test-pods create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"

    # update kubeconfig secret on service cluster
    echo "Updating the kubeconfig secret on service cluster with client cluster context"
    tanzu cluster kubeconfig get "${SERVICE_CLUSTER_NAME}" --admin
    kubectl config use-context "${SERVICE_CLUSTER_NAME}"-admin@"${SERVICE_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
        exit 1
    }

    # get what is in the secret for kubeconfig and then add to it
    kubectl -n prow get secrets/kubeconfig --template={{.data.config}} | base64 -d > "${KUBECONFIG_PATH}"
    cd "${K8S_TESTINFRA_PATH}"
    go run ./gencred --context="${CLIENT_CLUSTER_NAME}"-admin@"${CLIENT_CLUSTER_NAME}" --name="${CLIENT_CLUSTER_NAME}" --output="${KUBECONFIG_PATH}"
    cd "${REPO_PATH}"/config/prow

    kubectl -n prow delete secret kubeconfig
    kubectl -n prow create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"
}

function install_base_packages_on_client_cluster {

  echo "Installing base packages on PROW client cluster..."
  tanzu cluster kubeconfig get "${CLIENT_CLUSTER_NAME}" --admin
  kubectl config use-context "${CLIENT_CLUSTER_NAME}"-admin@"${CLIENT_CLUSTER_NAME}" || {
      error "CONTEXT SWITCH TO CLIENT CLUSTER FAILED!"
      exit 1
  }
  "${REPO_PATH}"/infra/aws/utils/add-tce-package-repo.sh || {
      error "PACKAGE REPOSITORY INSTALLATION FAILED!"
      exit 1
  }
  tanzu package available list || {
      error "UNEXPECTED FAILURE OCCURRED GETTING PACKAGE LIST!"
      exit 1
  }
  tanzu package install cert-manager --package-name cert-manager.community.tanzu.vmware.com --version 1.6.1 || {
    error "UNEXPECTED FAILURE OCCURRED INSTALLING CERT-MANAGER!"
    exit 1
  }
  tanzu package install contour --package-name contour.community.tanzu.vmware.com --version 1.18.1 -f ${REPO_PATH}/infra/aws/configs/prow-variable/contour-values.yaml || {
    error "UNEXPECTED FAILURE OCCURRED INSTALLING CONTOUR"
    exit 1
  }
}

# Create client cluster
create_client_cluster || exit 1

# Install packages on service cluster
install_base_packages_on_client_cluster || exit 1

install_prow_on_client_cluster || exit 1

echo "Prow client cluster build finished..."
echo "Please finish build with manual processes, i.e OIDC provider..."
