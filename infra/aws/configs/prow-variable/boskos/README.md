This overlay creates a fairly simple Boskos deployment in the namespace `test-pods`.

It manages the following resources:
- `aws-account` (cleaned by the aws janitor)

To try out this example, you will need to [install Kustomize](https://kubernetes-sigs.github.io/kustomize/installation/).

Additionally, to play with this example locally, you can first create a [kind cluster](https://kind.sigs.k8s.io/).


Steps to deploy boskos to a cluster:

**Step 1:** Create IAM User access-key/secret in your AWS console & add them as secret data to the `patch-aws-account/secret.yaml` file.

**Step 2:** Apply the boskos deployment:

```console
$ kustomize build . | kubectl apply -f-
$ kubectl apply -f patch-aws-account/secret.yaml
$ kubectl apply -f patch-aws-account/rbac.yaml
$ kubectl apply -f patch-aws-account/job.yaml
```
