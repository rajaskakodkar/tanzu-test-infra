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

# This script builds the Prow POC infrastructure using TCE clusters built on AWS
# It builds TCE, spins up a management cluster in AWS,
# creates a service and build cluster, and installs the default packages.
# Note: This is WIP and supports only Linux(Debian) and MacOS

# Please view the README.md for list of environment variables that need to be set

# aws-nuke is disabled because current "power user" rights do not have access to alias for account id

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

function delete_management_cluster {
    echo "$@"
    export CLUSTER_NAME="${MGMT_CLUSTER_NAME}"
    tanzu management-cluster delete "${CLUSTER_NAME}" -y || {
        collect_management_cluster_diagnostics "${CLUSTER_NAME}"
        delete_kind_cluster
        kubeconfig_cleanup "${CLUSTER_NAME}"
        #aws-nuke-tear-down "MANAGEMENT CLUSTER DELETION FAILED! Deleting the cluster using AWS-NUKE..." "${CLUSTER_NAME}"
    }
}

function nuke_management_and_service_clusters {
    export CLUSTER_NAME="${MGMT_CLUSTER_NAME}"
    kubeconfig_cleanup "${CLUSTER_NAME}"
    #aws-nuke-tear-down "Deleting the MANAGEMENT CLUSTER using AWS-NUKE..." "${CLUSTER_NAME}"
    export CLUSTER_NAME="${SERVICE_CLUSTER_NAME}"
    kubeconfig_cleanup "${CLUSTER_NAME}"
    #aws-nuke-tear-down "Deleting the WORKLOAD CLUSTER using AWS-NUKE..." "${CLUSTER_NAME}"
}

function nuke_management_and_child_clusters {
    export CLUSTER_NAME="${MGMT_CLUSTER_NAME}"
    kubeconfig_cleanup "${CLUSTER_NAME}"
    #aws-nuke-tear-down "Deleting the MANAGEMENT CLUSTER using AWS-NUKE..." "${CLUSTER_NAME}"
    export CLUSTER_NAME="${SERVICE_CLUSTER_NAME}"
    kubeconfig_cleanup "${CLUSTER_NAME}"
    #aws-nuke-tear-down "Deleting the WORKLOAD CLUSTER using AWS-NUKE..." "${CLUSTER_NAME}"
    export CLUSTER_NAME="${BUILD_CLUSTER_NAME}"
    kubeconfig_cleanup "${CLUSTER_NAME}"
    #aws-nuke-tear-down "Deleting the BUILD CLUSTER using AWS-NUKE..." "${CLUSTER_NAME}"
}

function delete_service_cluster {
    echo "$@"
    tanzu cluster delete "${SERVICE_CLUSTER_NAME}" --yes || {
        collect_management_and_service_cluster_diagnostics aws "${MGMT_CLUSTER_NAME}" "${SERVICE_CLUSTER_NAME}"
        nuke_management_and_service_clusters
        exit 1
    }
    for (( i = 1 ; i <= 120 ; i++))
    do
        echo "Waiting for service cluster to get deleted..."
        num_of_clusters=$(tanzu cluster list -o json | jq 'length')
        if [[ "$num_of_clusters" == "0" ]]; then
            echo "Service cluster ${SERVICE_CLUSTER_NAME} successfully deleted"
            break
        fi
        if [[ "$i" == 120 ]]; then
            echo "Timed out waiting for service cluster ${SERVICE_CLUSTER_NAME} to get deleted"
            echo "Using AWS NUKE to delete management and service clusters"
            collect_management_and_service_cluster_diagnostics aws "${MGMT_CLUSTER_NAME}" "${SERVICE_CLUSTER_NAME}"
            nuke_management_and_service_clusters
            exit 1
        fi
        sleep 5
    done
    # since tanzu cluster delete does not delete service cluster kubeconfig entry
    kubeconfig_cleanup "${SERVICE_CLUSTER_NAME}"
    echo "Service cluster ${SERVICE_CLUSTER_NAME} successfully deleted"
}

function delete_build_cluster {
    echo "$@"
    tanzu cluster delete "${BUILD_CLUSTER_NAME}" --yes || {
        nuke_management_and_child_clusters
        exit 1
    }
    for (( i = 1 ; i <= 120 ; i++))
    do
        echo "Waiting for build cluster to get deleted..."
        num_of_clusters=$(tanzu cluster list -o json | jq 'length')
        if [[ "$num_of_clusters" == "0" ]]; then
            echo "Service cluster ${BUILD_CLUSTER_NAME} successfully deleted"
            break
        fi
        if [[ "$i" == 120 ]]; then
            echo "Timed out waiting for build cluster ${BUILD_CLUSTER_NAME} to get deleted"
            echo "Using AWS NUKE to delete management and child clusters"
            nuke_management_and_child_clusters
            exit 1
        fi
        sleep 5
    done
    # since tanzu cluster delete does not delete service cluster kubeconfig entry
    kubeconfig_cleanup "${BUILD_CLUSTER_NAME}"
    echo "Build cluster ${BUILD_CLUSTER_NAME} successfully deleted"
}

function create_management_cluster {
    echo "Bootstrapping TCE management cluster on AWS..."
    # Set management cluster variables
    echo "Setting MANAGEMENT CLUSTER NAME to ${MGMT_CLUSTER_NAME}..."
    export CLUSTER_NAME="${MGMT_CLUSTER_NAME}"
    export CLUSTER_PLAN="${MGMT_CLUSTER_PLAN}"
    export CONTROL_PLANE_MACHINE_TYPE="${MGMT_CONTROL_PLANE_MACHINE_TYPE}"
    export NODE_MACHINE_TYPE="${MGMT_NODE_MACHINE_TYPE}"
    tanzu management-cluster create "${CLUSTER_NAME}" -f "${REPO_PATH}"/infra/aws/configs/cluster_config.yaml || {
        error "MANAGEMENT CLUSTER CREATION FAILED!"
        collect_management_cluster_diagnostics ${CLUSTER_NAME}
        delete_kind_cluster
        kubeconfig_cleanup ${CLUSTER_NAME}
        #aws-nuke-tear-down "Deleting management cluster" "${MGMT_CLUSTER_NAME}"
        exit 1
    }
    kubectl config use-context "${MGMT_CLUSTER_NAME}"-admin@"${MGMT_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO MANAGEMENT CLUSTER FAILED!"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
        error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
        collect_management_cluster_diagnostics ${MGMT_CLUSTER_NAME}
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
    tanzu management-cluster get | grep "${MGMT_CLUSTER_NAME}" | grep running || {
        error "MANAGEMENT CLUSTER NOT RUNNING!"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
}

function create_service_cluster {
    echo "Creating service cluster..."
    # Set service cluster variables
    echo "Setting WORKLOAD CLUSTER NAME to ${SERVICE_CLUSTER_NAME}..."
    export CLUSTER_NAME="${SERVICE_CLUSTER_NAME}"
    export CLUSTER_PLAN="${SERVICE_CLUSTER_PLAN}"
    export CONTROL_PLANE_MACHINE_TYPE="${SERVICE_CONTROL_PLANE_MACHINE_TYPE}"
    export NODE_MACHINE_TYPE="${SERVICE_NODE_MACHINE_TYPE}"
    tanzu cluster create "${CLUSTER_NAME}" -f "${REPO_PATH}"/infra/aws/configs/cluster_config.yaml || {
        error "SERVICE CLUSTER CREATION FAILED!"
        collect_management_and_service_cluster_diagnostics aws ${MGMT_CLUSTER_NAME} ${SERVICE_CLUSTER_NAME}
        nuke_management_and_service_clusters
        exit 1
    }
    tanzu cluster kubeconfig get "${SERVICE_CLUSTER_NAME}" --admin
    kubectl config use-context "${SERVICE_CLUSTER_NAME}"-admin@"${SERVICE_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
        delete_service_cluster "Deleting service cluster"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
        error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
        collect_management_and_service_cluster_diagnostics aws ${MGMT_CLUSTER_NAME} ${SERVICE_CLUSTER_NAME}
        delete_service_cluster "Deleting service cluster"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
}

function create_build_cluster {
    echo "Creating build cluster..."
    # Set service cluster variables
    echo "Setting BUILD CLUSTER NAME to ${BUILD_CLUSTER_NAME}..."
    export CLUSTER_NAME="${BUILD_CLUSTER_NAME}"
    export CLUSTER_PLAN="${BUILD_CLUSTER_PLAN}"
    export CONTROL_PLANE_MACHINE_TYPE="${BUILD_CONTROL_PLANE_MACHINE_TYPE}"
    export NODE_MACHINE_TYPE="${BUILD_NODE_MACHINE_TYPE}"
    tanzu cluster create "${CLUSTER_NAME}" -f "${REPO_PATH}"/infra/aws/configs/cluster_config.yaml || {
        error "BUILD CLUSTER CREATION FAILED!"
        collect_management_and_service_cluster_diagnostics aws ${MGMT_CLUSTER_NAME} ${BUILD_CLUSTER_NAME}
        nuke_management_and_child_clusters
        exit 1
    }
    tanzu cluster kubeconfig get "${BUILD_CLUSTER_NAME}" --admin
    kubectl config use-context "${BUILD_CLUSTER_NAME}"-admin@"${BUILD_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO BUILD CLUSTER FAILED!"
        delete_build_cluster "Deleting build cluster"
        delete_service_cluster "Deleting service cluster"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
    kubectl wait --for=condition=ready pod --all --all-namespaces --timeout=900s || {
        error "TIMED OUT WAITING FOR ALL PODS TO BE UP!"
        collect_management_and_service_cluster_diagnostics aws ${MGMT_CLUSTER_NAME} ${BUILD_CLUSTER_NAME}
        delete_build_cluster "Deleting build cluster"
        delete_service_cluster "Deleting service cluster"
        delete_management_cluster "Deleting management cluster"
        exit 1
    }
}

function replace_prow_variables {
    echo "Replacing prow variables..."

    # create new /prow and /job folders
    rm -rf "${REPO_PATH}"/config/prow
    rm -rf "${REPO_PATH}"/config/jobs
    cp -r "${REPO_PATH}"/infra/aws/configs/prow-variable "${REPO_PATH}"/config/prow
    cp -r "${REPO_PATH}"/infra/aws/configs/jobs-variable "${REPO_PATH}"/config/jobs

    # replace variables for core prow
    gsed -i -e "s/CERT_EMAIL/${CERT_EMAIL}/g" "${REPO_PATH}"/config/prow/cluster-issuer.yaml;
    gsed -i -e "s/PROW_FQDN/${PROW_FQDN}/g" "${REPO_PATH}"/config/prow/cluster/ingress.yaml;
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
    gsed -i -e "s/SECRETS_ROLE_ARN/${SECRETS_ROLE_ARN}/g" "${REPO_PATH}"/config/prow/cluster/external-secrets.yaml;
    gsed -i -e "s/SECRETS_ROLE_ARN/${SECRETS_ROLE_ARN}/g" "${REPO_PATH}"/config/prow/cluster/kubernetes-external-secrets_sa.yaml;

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
    go run ./gencred --context=prow-service-admin@prow-service --name=prow-service-trusted --output="${KUBECONFIG_PATH}"
    go run ./gencred --context=prow-service-admin@prow-service --name=default --output="${KUBECONFIG_PATH}"
    cd "${REPO_PATH}"/config/prow

    kubectl create clusterrolebinding cluster-admin-binding-"${USER}" \
  --clusterrole=cluster-admin --user="${USER}" || {
        error "CLUSTERROLEBINDING FAILED"
        exit 1
    }
    kubectl create ns prow || {
        error "CREATE NAMESPACE PROW FAILED!"
        exit 1
    }
    kubectl create ns test-pods || {
        error "CREATE NAMESPACE TEST-PODS FAILED!"
        exit 1
    }
    kubectl apply -f "${REPO_PATH}"/config/prow/cluster-issuer.yaml

    # secrets
    echo "Creating secrets..."
    kubectl -n prow create secret generic aws-access-key-id --from-literal=aws-access-key-id=${AWS_ACCESS_KEY_ID}
    kubectl -n prow create secret generic aws-access-key-secret --from-literal=aws-access-key-secret=${AWS_SECRET_ACCESS_KEY}

    if [ "$USE_EXTERNAL_SECRETS" = false ]; then

      kubectl -n prow create secret generic registry-username --from-literal=username=${REGISTRY_USERNAME}
      kubectl -n prow create secret generic registry-password --from-literal=password=${REGISTRY_PASSWORD}

      kubectl -n prow create secret generic gcs-credentials --from-file=${GCS_CREDENTIAL_PATH}
      kubectl -n test-pods create secret generic gcs-credentials --from-file=${GCS_CREDENTIAL_PATH}

      # create hmac token
      kubectl -n prow create secret generic hmac-token --from-file=hmac=${HMAC_TOKEN_PATH}

      # create github token
      kubectl -n prow create secret generic github-token --from-file=cert=${GITHUB_TOKEN_PATH} --from-literal=appid=${GITHUB_APP_ID}

      # create oauth token in test-pods for autobump to use
      kubectl -n test-pods create secret generic github-token --from-file=oauth=${OAUTH_TOKEN_PATH}

      # create github OAuth secrets
      kubectl -n prow create secret generic github-oauth-config --from-file=secret=${OAUTH_CONFIG_PATH}
      kubectl -n prow create secret generic cookie --from-file=secret=${COOKIE_PATH}

    fi

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

    # apply external secrets to test-pods ns
    if [ "$USE_EXTERNAL_SECRETS" = true ]; then
      kubectl apply -f "${REPO_PATH}"/config/prow/external-secrets.yaml
    fi

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
    go run ./gencred --context=prow-build-admin@prow-build --name=prow-build --output="${KUBECONFIG_PATH}"
    cd "${REPO_PATH}"/config/prow

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

    # update kubeconfig secret on service cluster
    echo "Updating the kubeconfig secret with build cluster context"
    tanzu cluster kubeconfig get "${SERVICE_CLUSTER_NAME}" --admin
    kubectl config use-context "${SERVICE_CLUSTER_NAME}"-admin@"${SERVICE_CLUSTER_NAME}" || {
        error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
        exit 1
    }
    kubectl -n prow delete secret kubeconfig
    kubectl -n prow create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"
    kubectl -n test-pods create secret generic kubeconfig --from-file=config="${KUBECONFIG_PATH}"
}

function install_base_packages_on_service_cluster {

  echo "Installing base packages on PROW service cluster..."
  tanzu cluster kubeconfig get "${SERVICE_CLUSTER_NAME}" --admin
  kubectl config use-context "${SERVICE_CLUSTER_NAME}"-admin@"${SERVICE_CLUSTER_NAME}" || {
      error "CONTEXT SWITCH TO SERVICE CLUSTER FAILED!"
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

# Create management, service, and build clusters
create_management_cluster || exit 1
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
