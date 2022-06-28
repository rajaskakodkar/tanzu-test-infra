
# Prow Secrets

## Overview

This document lists all types of Secrets used in the `prow-service` and `prow-gke-build` clusters, where all Prow Jobs are executed.
>**NOTE:** All Secrets are stored in the Google Secret Manager and synched to a namespace secret using External Secret Operator.


## prow-service cluster

| Prow Secret   | Description |
| :---------- | :---------------- |
| **hmac-token**| Used for validating GitHub webhooks.|
| **github-token**   | Stores the GitHub appid and cert |
| **cookie**   | Used in creating the OAuth token  |
| **oauth-token**| Personal access token called `prow-production` used by the `vmware-tanzu-prow-bot` GitHub user. |
| **slack-token** | OAuth token for the Slack bot user. It is used by Crier. |
| **kubeconfig**   | Kubernetes config files used by Deck to route jobs to correct build cluster  |
| **gcs-credentials**   | Grants write permissions for GCS log bucket  |

## prow-gke-build cluster

| Secret   | Description |
| :---------- | :---------------- |
| **gcs-credentials**   | Grants write permissions for GCS log bucket  |
| **preset-sa-reg-push**  | Grants write permissions to Artifact registry  |
| **preset-sa-vm-integration**  | Grants credentials to run integration tests on GCP VMs  |
| **preset-sa-gke-integration**  | Grants credentials to run integration tests on GKE clusters  |
| **preset-sa-artifacts**  | Grants write permissions to artifact bucket  |
| **preset-bot-github-token**  | GitHub token for vmware-tanzu-prow-bot  |
| **preset-sa-prow-job-resource-cleaner**  | Grants credentials to service account for cleaning up resources  |
