# Authorization

## Required GCP Permissions

To deploy a Prow cluster, configure the following service accounts in the GCP project you own.

| Service account name          | Usage                                                      | Required roles |
| :---------------------------- | :----------------------------------------------------------| :------------- |
| **prow-service-secrets**  | Provides access to Secret Manager for External Secrets Operator   | (`roles/iam.workloadIdentityUser`), (`roles/iam.serviceAccountTokenCreator`), (`roles/secretmanager.secretAccessor`)  |
| **prow-build-secrets**   | Provides access to Secret Manager for External Secrets Operator  | (`roles/iam.workloadIdentityUser`), (`roles/iam.serviceAccountTokenCreator`), (`roles/secretmanager.secretAccessor`)  |
| **prow-prod-publisher**   | Saves release and development artifacts to the Artifact registry.  | (`roles/artifactregistry.writer`)  |


## Kubernetes RBAC roles on Prow cluster

### Cluster Roles

The `cluster-admin` Cluster Role is the only Cluster Role required to deploy a Prow cluster. It is bound to the admin user deploying the Prow application.

### Roles

Following roles exist on Prow cluster:

| Role name   | Managed resources | Available actions |
| :---------- | :---------------- | :-------------- |
| **deck** | - `prowjobs.prow.k8s.io`  <br> - `pods/log` | get, list <br> get |
| **horologium** | - `prowjobs.prow.k8s.io`  <br> - `pods` | delete, list <br> delete, list |
| **plank** | - `prowjobs.prow.k8s.io` <br> - `pods` | create, list, update <br> create, list, delete |
| **sinker** | - `prowjobs.prow.k8s.io` <br> - `pods` | delete, list <br> delete, list |
| **hook** | - `prowjobs.prow.k8s.io` <br> - `configmaps` | create, get <br> get, update |
| **tide** | - `prowjobs.prow.k8s.io` |  create, list  |
| **crier** | - `prowjobs.prow.k8s.io` | get, watch <br> list, patch |

## User permissions on GitHub

Prow starts tests when triggered by certain Github events. For security reasons, the `trigger` plugin ensures that the test jobs are run only on pull requests (PR) created or verified by trusted users.

### Trusted users
All members of the `vmware-tanzu` organization are considered trusted users. The `trigger` plugin starts jobs automatically when a trusted user opens a PR or commits changes to a PR branch. Alternatively, trusted collaborators can start jobs manually through the `/test all`, `/test {JOB_NAME}` and `/retest` commands, even if a particular PR was created by an external user.

### External contributors
All users that are not members of the `vmware-tanzu` organization are considered external contributors. The `trigger` plugin does not automatically start test jobs on PRs created by external contributors. Furthermore, external contributors are not allowed to manually run tests on their own PRs.

> **NOTE:** External contributors can still trigger tests on PRs created by trusted users.

## Authorization decisions enforced by Prow

Actions on Prow can be triggered only by webhooks. To configure them you must create Github Secrets on your Prow cluster:
  - `hmac-token` - used to validate webhook
  - `github-token` - stores the GitHub appid and cert

A GitHub OAuth app is used to check on PR Status and to enable the rerun button on Prow Status. When OAuth is configured, Prow will perform GitHub actions on behalf of the authenticated users. This is necessary to fetch information about pull requests for the PR Status page and to authenticate users when checking if they have permission to rerun jobs via the rerun button on Prow Status.  This requires the following secrets in the Prow service cluster:

  - `cookie` - used in creating the OAuth token
  - `github-oauth-config` - stores GitHub OAuth specifics


TBD - describe vmware-tanzu-prow-bot.  This requires a Personal Access Token (PAT)


Kubernetes secrets are automated in the GKE Prow clusters using External Secrets Operator which synchronizes GCP Secret Manager secrets with Kubernetes secrets.  This is documented here: [Prow Secrets Management](./prow-secrets-management.md).
