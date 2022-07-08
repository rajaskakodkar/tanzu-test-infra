Creating GKE - Autopilot and Private

# set project id
gcloud init
gcloud auth login
gcloud config set project prow-open-btr
gcloud config list

# create prow-service
gcloud container --project "prow-open-btr" clusters create-auto "prow-service" --region "us-west1" --release-channel "regular" --enable-private-nodes --enable-master-authorized-networks --master-authorized-networks 75.192.40.0/24 --network "projects/prow-open-btr/global/networks/default" --subnetwork "projects/prow-open-btr/regions/us-west1/subnetworks/default" --cluster-ipv4-cidr "/17" --services-ipv4-cidr "/22"

# create prow-build
gcloud container --project "prow-open-btr" clusters create-auto "prow-build" --region "us-west1" --release-channel "regular" --enable-private-nodes --enable-master-authorized-networks --master-authorized-networks 75.192.40.0/24 --network "projects/prow-open-btr/global/networks/default" --subnetwork "projects/prow-open-btr/regions/us-west1/subnetworks/default" --cluster-ipv4-cidr "/17" --services-ipv4-cidr "/22"

# create a Cloud Router
gcloud compute routers create nat-router \
    --network default \
    --region us-west1

# add configuration to Cloud Router
gcloud compute routers nats create nat-config \
    --router-region us-west1 \
    --router nat-router \
    --nat-all-subnet-ip-ranges \
    --auto-allocate-nat-external-ips

# get creds
gcloud container clusters get-credentials prow-service --region=us-west1


# create gcs-publisher
$ gcloud iam service-accounts create prow-gcs-publisher
$ identifier="$(gcloud iam service-accounts list --filter 'name:prow-gcs-publisher' --format 'value(email)')"
$ gsutil mb gs://prow-gcs-publisher/ # step 2
$ gsutil iam ch allUsers:objectViewer gs://prow-gcs-publisher # step 3
$ gsutil iam ch "serviceAccount:${identifier}:objectAdmin" gs://prow-gcs-publisher # step 4
$ gcloud iam service-accounts keys create --iam-account "${identifier}" service-account.json # step 5
#$ kubectl -n test-pods create secret generic gcs-credentials --from-file=service-account.json # step 6
#$ kubectl -n prow create secret generic gcs-credentials --from-file=service-account.json

# create prow-andy-publisher
$ gcloud iam service-accounts create prow-andy-publisher
$ identifier="$(gcloud iam service-accounts list --filter 'name:prow-andy-publisher' --format 'value(email)')"
$ gsutil mb gs://prow-andy-publisher/ # step 2
$ gsutil iam ch allUsers:objectViewer gs://prow-andy-publisher # step 3
$ gsutil iam ch "serviceAccount:${identifier}:objectAdmin" gs://prow-andy-publisher # step 4
$ gcloud iam service-accounts keys create --iam-account "${identifier}" andy-service-account.json # step 5




# create secrets in secret manager
appid
cookie
gcs-publisher
github-key
github-oauth-config
hmac-token

# create service account
gcloud iam service-accounts create prow-service-secrets \
    --project=prow-open-btr

# add roles to service account - might not need, done to each secret below
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:GSA_NAME@GSA_PROJECT.iam.gserviceaccount.com" \
    --role "ROLE_NAME"

# bind service account to secrets
gcloud secrets add-iam-policy-binding appid \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding cookie \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding gcs-publisher \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding github-key \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding github-oauth-config \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding hmac-token \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

gcloud secrets add-iam-policy-binding kubeconfig \
    --member="serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"


# create service account
kubectl create ns prow
kubectl create serviceaccount prow-service-secrets-sa \
    --namespace prow

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding GSA_NAME@GSA_PROJECT.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:PROJECT_ID.svc.id.goog[NAMESPACE/KSA_NAME]"

gcloud iam service-accounts add-iam-policy-binding prow-service-secrets@prow-open-btr.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-open-btr.svc.id.goog[prow/prow-service-secrets-sa]"


# annotate KSA
kubectl annotate serviceaccount KSA_NAME \
    --namespace NAMESPACE \
    iam.gke.io/gcp-service-account=GSA_NAME@GSA_PROJECT.iam.gserviceaccount.com

kubectl annotate serviceaccount prow-service-secrets-sa \
    --namespace prow \
    iam.gke.io/gcp-service-account=prow-service-secrets@prow-open-btr.iam.gserviceaccount.com


# update pod spec
spec:
  serviceAccountName: KSA_NAME
  nodeSelector:
    iam.gke.io/gke-metadata-server-enabled: "true"



## pod based workoad identity - not working

# add role to GSA
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role roles/secretmanager.secretAccessor

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding prow-service-secrets@prow-open-btr.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-open-btr.svc.id.goog[prow/external-secrets]"

# install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n prow --set installCRDs=true

# annotate the sa
kubectl annotate serviceaccount external-secrets \
    --namespace prow \
    iam.gke.io/gcp-service-account=prow-service-secrets@prow-open-btr.iam.gserviceaccount.com

# delete the 3 pods

kubectl -n prow apply -f prow-service-secret-store.yaml
kubectl -n prow apply -f external-secrets-prow.yaml


## Use service accounts directly

# add roles to GSA
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role roles/secretmanager.secretAccessor

gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-service-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role roles/iam.serviceAccountTokenCreator

# create service account for prow ns
kubectl -n prow create serviceaccount prow-service-secrets-sa

# annotate the sa
kubectl annotate serviceaccount prow-service-secrets-sa \
    --namespace prow \
    iam.gke.io/gcp-service-account=prow-service-secrets@prow-open-btr.iam.gserviceaccount.com

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding prow-service-secrets@prow-open-btr.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-open-btr.svc.id.goog[prow/prow-service-secrets-sa]"

# install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets \
   --set installCRDs=true --create-namespace

kubectl -n prow apply -f cluster-secret-store-prow.yaml
kubectl -n prow apply -f external-secrets-prow.yaml


# create service account for test-pods ns
kubectl -n test-pods create serviceaccount prow-service-secrets-sa

# annotate the sa
kubectl annotate serviceaccount prow-service-secrets-sa \
    --namespace test-pods \
    iam.gke.io/gcp-service-account=prow-service-secrets@prow-open-btr.iam.gserviceaccount.com

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding prow-service-secrets@prow-open-btr.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-open-btr.svc.id.goog[test-pods/prow-service-secrets-sa]"

kubectl -n test-pods apply -f cluster-secret-store-test-pods.yaml
kubectl -n test-pods apply -f external-secrets-test-pods.yaml


Registry - artifact registry
prow-sandbox-registry

# create service account
gcloud iam service-accounts create prow-sandbox-registry-writer \
    --project=prow-open-btr

# add roles to service account
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-sandbox-registry-writer@prow-open-btr.iam.gserviceaccount.com" \
    --role "roles/artifactregistry.writer"

gcloud auth configure-docker us-west1-docker.pkg.dev

us-west1-docker.pkg.dev/prow-open-btr/prow-sandbox-registry-writer

# get internal creds
export KUBECONFIG=$KUBECONFIG_PATH
gcloud container clusters get-credentials prow-service --region=us-west1 --internal-ip




# ingress
gcloud compute addresses create prow-andy-ingress --global
gcloud compute addresses describe prow-andy-ingress --global
34.117.56.135

# set the IP to the FQDN: prow.andytauber.info





### build cluster

gcloud container clusters get-credentials prow-build --region=us-west1

kubectl create ns test-pods

kubectl create clusterrolebinding cluster-admin-binding \
      --clusterrole cluster-admin --user $(gcloud config get-value account)

kubectl apply --server-side=true -f https://raw.githubusercontent.com/kubernetes/test-infra/master/config/prow/cluster/prowjob-crd/prowjob_customresourcedefinition.yaml


# create gcp service account
gcloud iam service-accounts create prow-build-secrets \
    --project=prow-open-btr

#
# Add the service account to the secret as "Secret Manager Secret Accessor"
#

# add roles
gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-build-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role roles/secretmanager.secretAccessor

gcloud projects add-iam-policy-binding prow-open-btr \
    --member "serviceAccount:prow-build-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role roles/iam.serviceAccountTokenCreator

# bind service account to secrets
gcloud secrets add-iam-policy-binding gcs-publisher \
    --member="serviceAccount:prow-build-secrets@prow-open-btr.iam.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor"

# create service account for prow ns
kubectl -n test-pods create serviceaccount prow-build-secrets-sa

# annotate the sa
kubectl annotate serviceaccount prow-build-secrets-sa \
    --namespace test-pods \
    iam.gke.io/gcp-service-account=prow-build-secrets@prow-open-btr.iam.gserviceaccount.com

# bind KSA to GSA
gcloud iam service-accounts add-iam-policy-binding prow-build-secrets@prow-open-btr.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:prow-open-btr.svc.id.goog[test-pods/prow-build-secrets-sa]"

# install ESO
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets \
   --set installCRDs=true --create-namespace

kubectl -n test-pods apply -f prow-build-cluster-secret-store-test-pods.yaml
kubectl -n test-pods apply -f prow-build-external-secrets-test-pods.yaml


cp ~/.kube/config ~/.kube/config-gke
gcloud container clusters get-credentials prow-build --region=us-west1 --internal-ip

go run ./gencred --context="gke_prow-open-btr_us-west1_prow-build" --name=prow-gke-build --output="${KUBECONFIG_PATH}"
