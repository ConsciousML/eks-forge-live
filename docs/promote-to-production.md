{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
# Promote Your First Release

Now that you've completed [Deploy to Staging](/docs/deployment/get-started/deploy-to-staging/), you're ready to promote a new catalog version to `prod` through a pull request. You'll tag your catalog fork, bump `version_catalog` in a pull request, watch [CI](/docs/ci-cd/) test it on `staging`, and merge it so CD deploys `prod`. Finally, you'll destroy `prod`.

## Tag the Catalog
From the root of your [catalog fork](/docs/quickstart/installation/#fork-the-eks-forge-catalog), tag `main` and push the tag:
```bash
git checkout main
git pull
git tag v0.1.8-demo
git push origin v0.1.8-demo
```

## Bump the Catalog Version
From the root of your [live fork](/docs/deployment/get-started/live-repository-setup/#fork-the-live-repository), create a branch:
```bash
git checkout -b promote-demo
```

Set `version_catalog` to your new tag in both [`live/staging/eks/stack/terragrunt.stack.hcl`](../live/staging/eks/stack/terragrunt.stack.hcl) and [`live/prod/eks/stack/terragrunt.stack.hcl`](../live/prod/eks/stack/terragrunt.stack.hcl). CI tests the `staging` stack, and CD deploys the `prod` one:
```hcl
locals {
  version_catalog = "v0.1.8-demo"
  ...
}
```

Commit your change, push the branch, and open a pull request:
```bash
git commit -am "bump(catalog): to v0.1.8-demo"
git push -u origin promote-demo
gh pr create \
  --title "bump(catalog): to v0.1.8-demo" \
  --body "Promote catalog v0.1.8-demo to staging and prod."
```

## Watch CI
Opening the pull request triggers CI. Open the **Actions** tab of your live fork on GitHub, at `https://github.com/<your-github-owner>/<your-live-repo-name>/actions`. You should see a `CI` run for your pull request.

Click on it and watch the jobs run. After validating and planning `staging` and `prod`, the `check-pr-labels` job fails. Notice the comment CI posted on your pull request asking for the `run-terratest` label. See [CI/CD](/docs/ci-cd/) for what each job does.

CI also posted a **Production Plan Available** comment. Click the link to download the plan, unzip it, and open `prod-plan-output.html` in your browser. Since `prod` doesn't exist yet, every unit plans only additions:
```text
Plan: <n> to add, 0 to change, 0 to destroy.
```

## Run the Tests
Your repository doesn't have the `run-terratest` label yet. Create it, along with `skip-terratest` to skip the tests and `skip-cd` to skip the `prod` deployment on merge:
```bash
gh label create run-terratest
gh label create skip-terratest
gh label create skip-cd
```

Add the `run-terratest` label to your pull request. Adding a label doesn't trigger CI, so rerun the failed jobs of your latest `CI` run:
```bash
gh pr edit --add-label run-terratest
gh run rerun --failed $(gh run list --workflow CI --branch promote-demo --limit 1 --json databaseId --jq '.[0].databaseId')
```

Back in the **Actions** tab, `check-pr-labels` now passes and the `terratest` job starts. It deploys `staging`, runs the same tests you ran by hand in [Deploy to Staging](/docs/deployment/get-started/deploy-to-staging/#test-the-stack), and destroys it. See [Testing in CI/CD](/docs/ci-cd/testing/) for details. CI should take around 1 hour.

When every job is green, your pull request is ready to merge.

## Deploy to Production
Merge your pull request:
```bash
gh pr merge --merge --subject "bump(catalog): to v0.1.8-demo"
```

Merging to `main` triggers CD. In the **Actions** tab, you should see a `CD` run applying the `prod` stack. The deployment should take around 30 minutes.

## Check the Production Cluster
When CD is done, connect `kubectl` to your `prod` EKS cluster (replace `<region-code>` with the region you set in [`live/prod/region.hcl`](../live/prod/region.hcl)):
```bash
aws eks update-kubeconfig --region <region-code> --name prod-cluster
```

Check that ArgoCD deployed the Kubernetes resources:
```bash
kubectl get app -n argocd
```

When every application shows `Synced` and `Healthy`, your `prod` deployment succeeded:
```text
NAME                          SYNC STATUS   HEALTH STATUS
aws-lbc                       Synced        Healthy
cilium                        Synced        Healthy
external-secrets-operator     Synced        Healthy
podinfo                       Synced        Healthy
...
```

Your `prod` tools are also private. Connect to Tailscale by running `tailscale up`, and open Prometheus at `https://prometheus.private.prod.<base_domain>` (replace `<base_domain>` with the value from [`live/dns.hcl`](../live/dns.hcl)). You should see the Prometheus query page.

Notice the `private.prod` subdomain: `prod` gets its own, like `staging` and `dev`.

## Destroy Production
Like in `staging`, destroying the infrastructure removes the [Tailscale Connector](/docs/security/tailscale/#4-connector-and-split-dns), so you lose access to the cluster API. Before destroying the stack, disconnect from Tailscale by running `tailscale down`, or with the button in the Tailscale client.

Then, switch to `main` to get the code CD deployed, and destroy the infrastructure by running the following commands from the root of your live fork:
```bash
git checkout main
git pull
source .env
cd live/prod/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all destroy --non-interactive --no-stack-generate
```

Keep the `v0.1.8-demo` tag in your catalog fork: `main` now pins it, and CI and CD need it on your next pull request.

## What's Next
Next, see [Add a Unit](/docs/iac/add-a-unit/) to add a unit to your stack, then promote it the same way.

## Remove EKS Forge
:::warning
Your live fork's CI and CD rely on the bootstrap resources. Don't remove them if you plan to keep deploying `staging` and `prod`.
:::

Only if you want to remove EKS Forge from your AWS account entirely, follow [Remove EKS Forge](/docs/iac/remove-eks-forge/).
