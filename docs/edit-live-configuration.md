{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}

This guide shows you how to change the configuration of [`staging`](/docs/iac/#staging) and [`prod`](/docs/iac/#prod) from your [live fork](/docs/deployment/live-repository-setup/#fork-the-live-repository):
- The `values` your [units](/docs/iac/#units) receive.
- The shared `.hcl` files.
- The bootstrap pipelines.

You don't change any unit's code, so the catalog stays the same and you don't need to tag a new version. To change a unit's code, see [Add, Edit, or Remove a Unit](/docs/iac/add-a-unit/) instead.

First, create a branch in your live fork:
```bash
git checkout -b <branch>
```

## Edit the Stack Values

Edit the `values` of the unit you want to change in [`live/staging/eks/stack/terragrunt.stack.hcl`](../live/staging/eks/stack/terragrunt.stack.hcl) and [`live/prod/eks/stack/terragrunt.stack.hcl`](../live/prod/eks/stack/terragrunt.stack.hcl). Make the same change in both: CI only tests `staging`, so a change made only in `prod` reaches it untested. For example, to let Karpenter add more CPU to the `critical` NodePool:
```hcl
unit "karpenter_node_pool_critical" {
  ...
  values = {
    ...
    limits_cpu = "48" # was "32"
  }
}
```

If a value should differ between the two, mark it with a `# STAGING:` or `# PROD:` comment explaining why, like the existing ones:
```hcl
# live/prod/eks/stack/terragrunt.stack.hcl
# PROD: dev disables VPC flow logs to cut cost, prod enables them.
enable_flow_log = true
```

If you delete a `unit` block, see [Removed Units](/docs/iac/bump-the-catalog-version/#removed-units) first: you need its `path` to destroy its resources once CD has applied your change.

## Edit the Shared Configuration

The `.hcl` files at the root of `live/`, such as [`dns.hcl`](../live/dns.hcl) and [`network.hcl`](../live/network.hcl), are shared: a change there applies to both `staging` and `prod`. The files under `live/<env>/` and `live/<env>/eks/`, such as `region.hcl`, `domains.hcl`, and `vpc.hcl`, only apply to their environment. See the [HCL configuration reference](/docs/reference/hcl_configuration/) for what each file sets.

## Edit the Bootstrap Configuration

Each [bootstrap pipeline](/docs/deployment/live-repository-setup/#bootstrap) has its own stack file under `live/bootstrap/<pipeline>/`. Edit its stack or unit `values` there, the same way as in the EKS stacks. Pipelines with one stack per environment, such as `setup_dns/` and `slack/channels/`, have a `staging/` and a `prod/` folder: make the same change in both. See the [bootstrap reference](/docs/reference/bootstrap/) for each pipeline's inputs.

CI and CD never apply the bootstrap pipelines, so you apply your change yourself. From the root of your live fork, plan all of them at once:
```bash
source .env
cd live/bootstrap
terragrunt run --all plan
```

:::warning
This apply runs before your pull request is reviewed. Some bootstrap resources, such as GitHub Actions secrets, are shared by `staging` and `prod`, so a mistake here reaches `prod`. Read the plan carefully before applying.
:::

If the plan shows the changes you expect, apply them:
```bash
terragrunt run --all apply --non-interactive
```

## Roll Out to Staging and Prod

Commit your changes and push the branch, replacing `<message>` and `<branch>`:
```bash
git add -A
git commit -m "<message>" # e.g. "feat: raise critical nodepool cpu limit"
git push -u origin <branch>
```

Open a pull request with the label that fits your change, so CI can pass its `check-pr-labels` job:
- `run-terratest`: deploys `staging`, tests it end to end, and destroys it. Use it by default.
- `skip-terratest`: skips the `staging` tests. Use it only if you changed nothing but docs.

```bash
gh pr create --title "<message>" --body "<description>" --label run-terratest # or skip-terratest
```

Before merging, download the production plan from the **Production Plan Available** comment CI posts on your pull request, and check what it changes in `prod`, see [Watch CI](/docs/deployment/promote-to-production/#watch-ci). If a job fails, see [Troubleshoot Live CI](/docs/ci-cd/per-repository/troubleshoot-live-ci/). When every job is green, merge:
```bash
gh pr merge --merge
```

Merging to `main` triggers CD, which applies your change to `prod`. See [Deploy to Production](/docs/deployment/promote-to-production/#deploy-to-production) to check the deployment.

If you deleted a `unit` block from the EKS stacks, destroy it in `prod` once CD succeeds, see [Destroy Removed Units](/docs/iac/bump-the-catalog-version/#destroy-removed-units).
