# Presets

This document contains the list of all Presets available in the [`config.yaml`](../../prow/config.yaml) file. Use them to define Prow Jobs for your components.

This is a work in progress.

| Name                                                      | Description                                                                                                                                                                               |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **preset-dind-enabled**                                   | It allows Docker to run in your job. You still need to launch Docker in your job.                                                                                                         |
| **preset-kind-volume-mounts**                             | It allows KinD (Kubernets in Docker) to run in your job.                                                                                                                                  |
| **preset-sa-reg-push**                                    | It injects credentials for pushing images to Google Artifact Registry .                                                                                                                 |
| **preset-build-pr**                                       | It provides the environment variable with the location of the directory in the Docker repository for storing images. It also sets the **BUILD_TYPE** variable to `pr`.                    |
| **preset-gc-project-env**                                 | It provides the environment variable with the Google Cloud Platform (GCP) project name.                                                                                                   |
| **preset-gc-compute-envs**                                | It provides environment variables with the GCP compute zone and the GCP compute region.                                                                                                   |
| **preset-sa-vm-integration**                              | It injects credentials for the service account to run integration tests on virtual machines (VMs).                                                                                        |
| **preset-sa-gke-integration**                             | It injects credentials for the service account to run integration tests on a Google Cloud Engine (GKE) cluster.                                                                           |
| **preset-build-console-main**                           | It defines the environment variable with the location of the directory in the Docker repository for storing Docker images from the `console` repository. It also sets the **BUILD_TYPE** variable to `main`. |
| **preset-sa-artifacts**                                  | It sets up the service account that has `write` rights to the artifacts bucket. This is also required if you need to push a new docker image.                                      |
| **preset-bot-github-token**                               | It sets the environment variable with the GitHub token for the `vmware-tanzu-prow-bot` account.                                                                                                        |
| **preset-bot-github-identity**                            | It sets the environment variables for the name and email of the `vmware-tanzu-prow-bot` account.                                                                                                       |
| **preset-slack-notifications**          | It defines a webhook URL and a client token required for the Slack integration.                                                                                                          |
| **preset-sa-prow-job-resource-cleaner**                   | It injects credentials for the service account to give multiple resource cleaners the `list` and `delete` rights in GCP.                                                                  |
