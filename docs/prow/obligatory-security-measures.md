# Obligatory security measures

The `vmware-tanzu` Prow project has implemented security measures to take on a periodic basis and when a vmware-tanzu organization member leaves the project.

## Change Secrets regularly

All Secrets used in the Prow production cluster must be changed every six months. Follow the [Prow secret management](./prow-secrets-management.md) guidelines to create new Secrets. Once the new Secrets are updated in GCP Secret Manger, the External Secrets Operator changes all Kubernetes secrets in the Prow clusters automatically.

The kubeconfig file used by Prow to access build clusters is stored as a secret and uses a token to gain access to the cluster.  We will create an automated job that creates new tokens once a day and stores them in GCP Secret Manager for retrieval by the External Secrets Operator on the Prow service cluster.

## Preventive measures

Make sure that jobs do not include any Secrets that are available in the output as this can lead to severe security issues.

## Offboarding checklist

When a `vmware-tanzu` organization member with access to the Prow cluster leaves the project, take the necessary steps to keep `vmware-tanzu` assets secure.

### Remove Google project access

Remove and admin from the `prow-tkg-build` Google project immediately after they leave the project. Follow [this](https://cloud.google.com/iam/docs/granting-changing-revoking-access) document to revoke necessary access.

### Change Secrets

Change all Secrets that were valid when the person was a project member. Follow the [Prow secret management](./prow-secrets-management.md) guidelines to create new Secrets. Once the new Secrets are updated in GCP Secret Manger, the External Secrets Operator changes all Kubernetes secrets in the Prow clusters automatically.

### Cluster API Server access

Cluster access to the API Server via the kubectl CLI is restricted to an IP access list.  Even if you have sufficient rights in the GCP project, you will need to add your client IP CIDR to the cluster's access list.
