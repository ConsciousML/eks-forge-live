{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
# Deploy to Staging

Now that you've completed [Live Repository Setup](/docs/deployment/live-repository-setup/), you're ready to deploy the EKS stack in the [`staging` environment](/docs/iac/#staging).

## Run the Terragrunt Stack
From the root of your live fork, run the following commands to deploy the `staging` environment:

```bash
source .env
cd live/staging/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

The deployment should take around 30 minutes.

While it runs, open [`live/staging/eks/stack/terragrunt.stack.hcl`](../live/staging/eks/stack/terragrunt.stack.hcl) and look at two places. First, `version_catalog` at the top of the `locals` block. Then, the `source` of the first [unit](/docs/iac/#units), `unit "vpc"`, right below `locals`:
```hcl
locals {
  version_catalog = "v0.1.8"
  ...
}

unit "vpc" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/vpc/vpc?ref=${local.version_catalog}"
  ...
}
```

In `dev`, the catalog used units from its own local paths. Here, live pulls them from your catalog fork on GitHub, pinned to the `version_catalog` tag.

## Connect to the Cluster
When the deployment is done, connect `kubectl` to your `staging` EKS cluster (replace `<region-code>` with the region you set in [`live/staging/region.hcl`](../live/staging/region.hcl)):
```bash
aws eks update-kubeconfig --region <region-code> --name staging-cluster
```

Check which cluster `kubectl` now points at:
```bash
kubectl config current-context
```

You should see your `staging` cluster:
```text
arn:aws:eks:<region-code>:<account-id>:cluster/staging-cluster
```

The tests you'll run later use this context.

ArgoCD then deploys the Kubernetes resources. Monitor the progress by running:
```bash
kubectl get app -n argocd
```

When every application shows `Synced` and `Healthy`, the deployment succeeded:
```text
NAME                          SYNC STATUS   HEALTH STATUS
aws-lbc                       Synced        Healthy
cilium                        Synced        Healthy
external-secrets-operator     Synced        Healthy
podinfo                       Synced        Healthy
...
```

## Log In to ArgoCD
Like in `dev`, ArgoCD is only reachable using Tailscale. Connect to Tailscale by running `tailscale up`, or with the button in the Tailscale client.

Open `https://argocd.private.staging.<base_domain>` in your browser (replace `<base_domain>` with the value from [`live/dns.hcl`](../live/dns.hcl)) and log in with username `admin`. Retrieve the password with:
```bash
aws secretsmanager get-secret-value \
  --secret-id staging-argocd-password \
  --query SecretString \
  --output text | jq -r .plaintext
```

You should see the same applications as in the `kubectl get app` output above.

Notice the URL: `private.staging` instead of `private.dev`. Each [environment](/docs/iac/#environments) has its own EKS cluster, VPC, Terraform state, and DNS subdomain, so `dev` and `staging` can run side by side.

## Test the Stack
You can apply and destroy `staging` by hand, as you just did, but its main purpose is to test the full infrastructure end to end. Now, run the same tests as CI against the cluster you just deployed.

Keep Tailscale connected: the tests reach your private endpoints. From the root of your live fork, run the following, replacing `<region-code>` with the region you set in `live/staging/region.hcl`:
```bash
export AWS_REGION=<region-code>
go test -v -run '^TestStackExists$' ./tests/... -timeout 10m
```

The tests check that ArgoCD deployed every application and that your cluster's tools are reachable. See [Testing in CI/CD](/docs/ci-cd/testing/) for the full list. You should see:
```text
...
--- PASS: TestStackExists (...)
PASS
```

What you just did by hand, [CI](/docs/ci-cd/) does automatically on pull requests: it deploys `staging`, runs these same tests with [Terratest](https://terratest.gruntwork.io/), and destroys it. This way, you only merge changes that deploy a working infrastructure.

## Destroy the Infrastructure
CI deploys to the same `staging` environment as you. Destroy your cluster before moving on, so it doesn't collide with CI in the next step.

Like in `dev`, destroying the infrastructure removes the [Tailscale Connector](/docs/security/tailscale/#4-connector-and-split-dns), so you lose access to the cluster API. Before destroying the stack, disconnect from Tailscale by running `tailscale down`, or with the button in the Tailscale client.

Finally, destroy the infrastructure by running the following commands from the root of your live fork:
```bash
source .env
cd live/staging/eks/stack
terragrunt run --all destroy --non-interactive --no-stack-generate
```

## What's Next
Next, see [Promote to Production](/docs/deployment/promote-to-production/) to ship your changes through a pull request.
