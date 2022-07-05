# Prow Secrets Management

## Overview

The vmware-tanzu Prow project makes use of the External Secrets Operator (ESO) to synchronize secrets located in a cloud secret manager with Kubernetes secrets.  Both GKE and EKS allow Kubernetes service accounts to be mapped to cloud service accounts.  ESO uses a Kubernetes service account to gain permissions to read secrets in the cloud secret manager.

External-secrets runs within the Kubernetes cluster as a deployment resource. It utilizes CustomResourceDefinitions to configure access to secret providers through SecretStore resources and manages Kubernetes secret resources with ExternalSecret resources.

Referenced from: https://external-secrets.io/

## Prerequisites

 - Kubernetes cluster (> 1.16.0)
 - Access to the Google project or AWS Secret Manager
 - Admin access to the prow-service and prow-gke-build clusters

## Google Secret Management

When you communicate for the first time with Google Cloud, set the context to your Google Cloud project. Run this command:
```
gcloud config set project $PROJECT
```

### Add secrets to Google Secret Manager

Add each secret to Secret Manager.  Google Secret Manager is not multi-key like AWS Secrets Manager so each secret will only contain one value.  ESO has the ability to build a multi key Kubernetes secret by attaching multiple Google Secret Manager secrets.

### Create Google Service Accounts needed for ESO

Use this command to create the Google service accounts - one for each cluster.
```
# create secrets service accounts
gcloud iam service-accounts create prow-service-secrets \
    --project=prow-tkg-build

gcloud iam service-accounts create prow-build-secrets \
    --project=prow-tkg-build
```

Bind the Google service account to the secrets.  The following example should be replicated for all service accounts / secrets:

```
gcloud secrets add-iam-policy-binding gcs-publisher \
    --member="serviceAccount:prow-build-secrets@prow-tkg-build.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"
```

Add required roles to the Google service accounts:
```
# add roles to GSA
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-service-secrets@prow-tkg-build.iam.gserviceaccount.com" \
    --role roles/secretmanager.secretAccessor

gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-service-secrets@prow-tkg-build.iam.gserviceaccount.com" \
    --role roles/iam.serviceAccountTokenCreator
```

### Create the Kubernetes service account

Repeat for the service account for each build cluster.  Note the namespace/service in the binding command.

```
kubectl create serviceaccount prow-service-secrets-sa \
    --namespace prow

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding prow-service-secrets@prow-tkg-build.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-tkg-build.svc.id.goog[prow/prow-service-secrets-sa]"

# annotate KSA
kubectl annotate serviceaccount prow-service-secrets-sa \
    --namespace prow \
    iam.gke.io/gcp-service-account=prow-service-secrets@prow-tkg-build.iam.gserviceaccount.com
  ```

### Install External Secrets Operator

Use helm to install ESO into its own namespace:

   ```
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets \
      --set installCRDs=true --create-namespace
   ```

### Define the Secrets Store

The Secrets store tells ESO where the Google secrets are located (project and region) and which Kubernetes service account to use to access the secrets.  Create this on the prow-service cluster and repeat for each build cluster:

   ```
   apiVersion: external-secrets.io/v1beta1
   kind: ClusterSecretStore
   metadata:
     name: prow-service-secretstore
   spec:
     provider:
       gcpsm:
         projectID: prow-tkg-build
         auth:
           workloadIdentity:
             # name of the cluster region
             clusterLocation: us-west1
             # name of the GKE cluster
             clusterName: prow-service
             # projectID of the cluster (if omitted defaults to spec.provider.gcpsm.projectID)
             # clusterProjectID: my-cluster-project
             # reference the sa from above
             serviceAccountRef:
               name: prow-service-secrets-sa
               namespace: prow
   ```

### Define secrets to create in the Kubernetes namespace

The following example is of one secret.  Repeat example for each secret. Create this on the prow-service cluster and repeat for each build cluster:
```
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gcs-credentials
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: prow-service-secretstore
    kind: ClusterSecretStore
  target:
    name: gcs-credentials
    creationPolicy: Owner
  data:
  - secretKey: "service-account.json"
    remoteRef:
      key: gcs-publisher
```

The Google Secret Manager is checked and the Kubernetes secrets updated every minute.

## AWS Secret Management

When you communicate for the first time with AWS Cloud, you will need to do the initial configuration:
```
aws configure
```

Also set the needed environment variables:
```
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
export AWS_REGION=us-west-1
```

### Add secrets to Google Secret Manager

Add each secret to Secret Manager.  AWS secrets are stored as a key / value combination.  For guidance on how to create secrets in AWS Secrets Manager, see [AWS Secrets Guidance](https://confluence.eng.vmware.com/display/TKG/How+To%3A+setup+prow+secrets+in+AWS+Secrets+Manager).

### Add OIDC provider
Use following as guide - https://docs.aws.amazon.com/eks/latest/userguide/enable-iam-roles-for-service-accounts.html
Note name of OIDC provider: `oidc=oidc.eks.us-west-1.amazonaws.com/id/ABB064782EBD6E07D6BE1932CE4B23C1`

### Add Prow Service Cluster IP to Allowed IP ranges
nat-auto-ip for prow-service is 34.168.63.192

### Create IAM Policy and Role in AWS IAM

Policy: prow-secrets-manager-policy
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetRandomPassword",
                "secretsmanager:ListSecrets"
            ],
            "Resource": "*"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": "secretsmanager:*",
            "Resource": "arn:aws:secretsmanager:*:605126514283:secret:prow/*"
        }
    ]
}
```

Role: prow-secrets-manager-role-prow-aws-build
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::605126514283:oidc-provider/oidc.eks.us-west-1.amazonaws.com/id/ABB064782EBD6E07D6BE1932CE4B23C1"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.us-west-1.amazonaws.com/id/ABB064782EBD6E07D6BE1932CE4B23C1:sub": "system:serviceaccount:test-pods:aws-secrets-sa",
                    "oidc.eks.us-west-1.amazonaws.com/id/ABB064782EBD6E07D6BE1932CE4B23C1:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
```


### Create Kubernetes service account in namespace `test-pods`

First create cluster role binding if not there:
```
# cluster role binding
kubectl create clusterrolebinding cluster-admin-binding-"${USER}" \
  --clusterrole=cluster-admin --user="${USER}"
```

Then create the service account in the `test-pods` namespace:
```
apiVersion: v1
kind: ServiceAccount
metadata:
  name: aws-secrets-sa
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::605126514283:role/prow-secrets-manager-role-prow-aws-build
```

### Install External Secrets Operator

Use helm to install ESO into its own namespace:

   ```
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets \
      --set installCRDs=true --create-namespace
   ```

### Define the Secrets Store

The Secrets store tells ESO where the AWS Secrets Manager secrets are located (region) and which Kubernetes service account to use to access the secrets.  Create this on the prow-eks-build cluster in the `test-pods` namespace.

   ```
   apiVersion: external-secrets.io/v1beta1
   kind: SecretStore
   metadata:
     name: secretstore-us-west-1
   spec:
     provider:
       aws:
         service: SecretsManager
         region: us-west-1
         auth:
           jwt:
             serviceAccountRef:
               name: aws-secrets-sa
   ```

### Define secrets to create in the Kubernetes namespace

The following example is of one secret.  Repeat example for each secret. Create this on the prow-eks-build cluster in the  `test-pods` namespace:
```
---
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: gcs-credentials
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: secretstore-us-west-1
    kind: SecretStore
  target:
    name: gcs-credentials
    creationPolicy: Owner
  data:
  - secretKey: "service-account.json"
    remoteRef:
      key: prow/gcs-credentials
```

The AWS Secrets Manager is checked and the Kubernetes secrets updated every minute.
