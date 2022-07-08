## Setting up IAP
Use the following guide: [iap guide](https://cloud.google.com/iap/docs/enabling-kubernetes-howto)

- go to APIs --> OAuth consent screen --> select External
- App name = vmware-tanzu-prow-prod
- User support email = tkg-prow-team@groups.vmware.com
- Developer contact email = tkg-prow-team@groups.vmware.com

Note the id and secret and create env variables:
```
export CLIENT_ID ="583654837350-6vk728eqcbqomjv0oetuohl5u404a8rk.apps.googleusercontent.com"
export CLIENT_SECRET="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"
```
The redirect URI will be:
```
https://iap.googleapis.com/v1/oauth/clientIds/$CLIENT_ID:handleRedirect
```

Make note of the Load Balancer tied to the ingress backend.  There will two LBs tied to the Ingress: one for Deck and one for Hook.  Pick the one for Deck.
```
export PROJECT="prow-tkg-build"
export INGRESS_BACKEND: k8s2-um-1c369g9e-prow-prow-0dzmeypz
```

Tie the client_id and secret to the backend service.  This will set HTTPS Resource status in IAP UI to "OK"
```
gcloud beta compute backend-services update $INGRESS_BACKEND --project=$PROJECT --global --iap=enabled,oauth2-client-id=$CLIENT_ID,oauth2-client-secret=$CLIENT_SECRET
```

### create secret
```
kubectl -n prow create secret generic iap-secret --from-literal=client_id=$CLIENT_ID \
  --from-literal=client_secret=$CLIENT_SECRET
```

Move to directory: /tanzu-test-infra/infra/gcp/ingress to create the backend and update the deck service:
```
kubectl -n prow apply -f backend-config-iap.yaml

# annotate the deck service account
kubectl -n prow apply -f deck-svc.yaml
```
