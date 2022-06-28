# Production Cluster Configuration

## Overview

This instruction provides the steps required to deploy a production cluster for Prow.

## Prerequisites

Use the following tools and configuration:

- Kubernetes 1.10+ on Google Kubernetes Engine (GKE)
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/) to communicate with Kubernetes
- [gcloud](https://cloud.google.com/sdk/gcloud/) to communicate with Google Cloud Platform (GCP)
- The `vmware-tanzu-prow-bot` GitHub account
- [Kubernetes cluster](./prow-installation.md#provision-a-main-prow-cluster)
- Secrets in the Kubernetes cluster:
  - `hmac-token` which is a Prow HMAC token used to validate GitHub webhooks
  - `oauth-token` which is a GitHub token with read and write access to the `vmware-tanzu` account
- One bucket on Google Cloud Storage (GCS) for storing logs
- GCP configuration that includes:
  - A [global static IP address](https://cloud.google.com/compute/docs/ip-addresses/reserve-static-external-ip-address) with the `prow-static-ingress` name


## Installation

1. Prepare the workload cluster:

  ```bash
    export WORKLOAD_CLUSTER_NAME=prow-gke-build
    export ZONE=us-west1-a
    export PROJECT=prow-tkg-build
  ```

    ### In GKE get KUBECONFIG for cluster prow-gke-build
  ```bash
    gcloud container clusters get-credentials $WORKLOAD_CLUSTER_NAME --zone=$ZONE --project=$PROJECT
  ```

    TBD

2. Set the context to your Google Cloud project.

    Export the **PROJECT** variable and run this command:

  ```bash
    gcloud config set project $PROJECT
  ```

3. Make sure that kubectl points to the Prow main cluster.

  Export these variables:

  ```bash
  export WORKLOAD_CLUSTER_NAME=prow-gke-build
  export ZONE=us-west1-a
  export PROJECT=prow-tkg-build
  ```

   For GKE, run the following command:

   TBD

4. Export this environment variable:

  ```bash
    export GOPATH=$GOPATH ### Ensure GOPATH is set
  ```

5. Run the following script to create a Kubernetes Secret resource in the main Prow cluster. This way the main Prow cluster can access the workload cluster:

  TBD

>**NOTE:** Create the workload cluster first and make sure the **local** kubeconfig for the Prow admin contains the context for this cluster. Point the **current** kubeconfig to the main Prow cluster.

6. Run the following script to start the installation process:

  TBD

   The installation script performs the following steps to install Prow:

   - Creates a Cluster Role Binding
   - Deploys Prow components
   - Creates the GKE cert-manager cert for prow.tanzu.io
   - Deploys secure Ingress

7. Verify the installation.

   To check if the installation is successful, perform the following steps:

   - Check if all Pods are up and running:
     `kubeclt get pods`
   - Check if the Deck is accessible from outside of the cluster:
     `kubectl get ingress prow`
   - Copy the address of the `prow` Ingress and open it in a browser to display the Prow status on the dashboard.

## Configure Prow

When you use the [`install-prow.sh`](../../prow/scripts/install-prow.sh) script to install Prow on your cluster, the list of plugins and configuration is empty. You can configure Prow by specifying the `config.yaml` and `plugins.yaml` files, and adding job definitions to the `jobs` directory.

### The config.yaml file

The `config.yaml` file contains the basic Prow configuration. When you create a particular Prow job, it uses the Preset definitions from this file. See the example of such a file [here](../../prow/config.yaml).

For more details, see the [Kubernetes documentation](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#adding-more-jobs).

### The plugins.yaml file

The `plugins.yaml` file contains the list of [plugins](https://status.build.kyma-project.io/plugins) you enable on a given repository. See the example of such a file [here](../../prow/plugins.yaml).

For more details, see the [Kubernetes documentation](https://github.com/kubernetes/test-infra/tree/master/prow/plugins#plugins).

### The jobs directory

The `jobs` directory contains the Prow jobs configuration. See the example of such a file [here](../../prow/jobs).

For more details, see the [Kubernetes documentation](https://github.com/kubernetes/test-infra/blob/master/prow/getting_started_deploy.md#adding-more-jobs).

### Verify the configuration

To check if the `plugins.yaml`, `config.yaml`, and `jobs` configuration files are correct, run the `validate-config.sh {plugins_file_path} {config_file_path} {jobs_dir_path}` script. For example, run:

```bash
  ./validate-config.sh ../prow/plugins.yaml ../prow/config.yaml ../prow/jobs
```

### Upload the configuration on a cluster

If the files are configured correctly, upload the files on a cluster.

1. Use the `update-plugins.sh {file_path}` script to apply plugin changes on a cluster.

   ```bash
   ./update-plugins.sh ../prow/plugins.yaml
   ```

2. Use the `update-config.sh {file_path}` script to apply Prow configuration on a cluster.

   ```bash
   ./update-config.sh ../prow/config.yaml
   ```

3. Use the `update-jobs.sh {jobs_dir_path}` script to apply jobs configuration on a cluster.

   ```bash
   ./update-jobs.sh ../prow/jobs
   ```

After you complete the required configuration, you can test the uploaded plugins and configurations. You can also create your own job pipeline and test it against the forked repository.

### Cleanup

To clean up everything created by the installation script, run the removal script:

```bash
./remove-prow.sh
```
