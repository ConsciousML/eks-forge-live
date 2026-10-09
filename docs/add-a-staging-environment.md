{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}

This guide shows you how to deploy a second [`staging`](/docs/iac/#staging)-like environment from your [live fork](/docs/deployment/get-started/live-repository-setup/#fork-the-live-repository) (e.g. `staging-2`), running next to `staging`. It deploys the same stack under another name, with its own state, VPC, cluster, hosted zone, and Slack channels.

You deploy and update it by hand: CI only tests `staging`, and CD only applies `prod`. To wire another environment into them, see [Limitations & Improvements](/docs/ci-cd/limitations-and-improvements/).

It assumes you've already deployed `staging` once, as in [Deploy to Staging](/docs/deployment/get-started/deploy-to-staging/). For a `dev`-like environment in your catalog fork, see [Add a Dev Environment](/docs/iac/add-a-dev-environment/) instead.

First, create a branch in your live fork, replacing `<branch>`:
```bash
git checkout -b <branch>
```

Then export your environment's name, replacing `<environment>` (e.g. `staging-2`). Use only lowercase letters, digits, and hyphens, since it ends up in bucket names and hostnames:
```bash
export ENVIRONMENT=<environment>
```

The commands of this guide read it, so run them all from the same shell.

## Reserve a VPC CIDR

In your [catalog fork](/docs/quickstart/installation/#fork-the-eks-forge-catalog), add your environment to `vpc_cidrs` in [`pipelines/network.hcl`](https://github.com/ConsciousML/eks-forge-catalog/blob/main/pipelines/network.hcl), with the `/16` block that follows the highest one. For example, for `staging-2`:
```hcl
vpc_cidrs = {
  ...
  catalog-eks-ci = "10.3.0.0/16"
  staging-2      = "10.4.0.0/16"
}
```

Then add the same entry to [`live/network.hcl`](../live/network.hcl) in your live fork:
```hcl
vpc_cidrs = {
  prod      = "10.0.0.0/16"
  staging   = "10.1.0.0/16"
  staging-2 = "10.4.0.0/16"
}
```

You need both: the stack reads its VPC CIDR from the live entry, and the Tailscale ACL is built from the catalog one. The block must not overlap another environment's in either file, since Tailscale routes each VPC by its CIDR.

## Approve the CIDR in Tailscale

The [Tailscale ACL](/docs/reference/bootstrap/tailscale_acl/) pipeline only runs from your catalog fork. There, commit the CIDR on a branch and push it, replacing `<branch>`. The pipeline fetches its unit from git at your current branch, so it must exist on GitHub:
```bash
git checkout -b <branch>
git commit -am "feat: add $ENVIRONMENT vpc cidr"
git push -u origin <branch>
```

Without your CIDR in the ACL's `autoApprovers`, the environment's [Tailscale Connector](/docs/security/tailscale/#4-connector-and-split-dns) can't route traffic into its VPC. From the root of your catalog fork, apply the pipeline again:
```bash
source .env
cd pipelines/bootstrap/tailscale/acl
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Then follow [Open a Pull Request](/docs/iac/add-a-unit/#open-a-pull-request) and [Merge](/docs/iac/add-a-unit/#merge). You don't need to tag the catalog: your live fork reads its own `network.hcl`.

## Create the Hosted Zone

Each environment gets its own public hosted zone, at `<environment>.<base_domain>`. From the root of your live fork, copy the one of `staging`:
```bash
cp -r live/bootstrap/setup_dns/staging live/bootstrap/setup_dns/$ENVIRONMENT
```

In its `environment.hcl`, set `environment` to your environment's name. For example, for `staging-2`:
```hcl
# live/bootstrap/setup_dns/staging-2/environment.hcl

locals {
  environment       = "staging-2"
  environment_alias = local.environment
}
```

Then apply it:
```bash
source .env
cd live/bootstrap/setup_dns/$ENVIRONMENT/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Finally, add the hosted zone's NS records in your domain registrar, by following [Setup DNS](/docs/deployment/get-started/live-repository-setup/#setup-dns) from the `terragrunt stack output` command. Without them, ACM can't validate the environment's TLS certificate.

## Create the Slack Channels

Alertmanager posts to channels prefixed with the environment's name (e.g. `staging-2-k8s-critical`). From the root of your live fork, copy the channels pipeline of `staging`:
```bash
cp -r live/bootstrap/slack/channels/staging live/bootstrap/slack/channels/$ENVIRONMENT
```

Set `environment` in its `environment.hcl`, as in [Create the Hosted Zone](#create-the-hosted-zone). Then apply it:
```bash
source .env
cd live/bootstrap/slack/channels/$ENVIRONMENT/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Finally, join the new channels in your Slack workspace, as in [Slack Bootstrap](/docs/quickstart/bootstrap/slack/).

## Check Quota Headroom

The EC2 quotas are shared by every environment of your AWS account, and another cluster adds its own vCPUs to them. Before you deploy, follow [Check Quota Headroom First](/docs/compute/increase-ec2-capacity/#check-quota-headroom-first).

## Create the Environment

From the root of your live fork, copy the `staging` environment:
```bash
cp -r live/staging live/$ENVIRONMENT
```

In its `environment.hcl`, set `environment` to your environment's name and keep `environment_alias` as `staging`. For example, for `staging-2`:
```hcl
# live/staging-2/environment.hcl

locals {
  environment       = "staging-2"
  environment_alias = "staging"
}
```

Every resource name, hostname, and state bucket derives from `environment`. `environment_alias` makes the apps load the [environment overlays](/docs/applications/how-the-app-of-apps-works/#environment-overlays) of `staging`, since your environment has none of its own. To give it its own overlays instead, see [Configure an App per Environment](/docs/applications/configure-an-app-per-environment/).

If your environment targets another AWS region, also set `region` and `azs` in its `region.hcl`.

## Deploy the Environment

From the root of your live fork, deploy its stack:
```bash
source .env
cd live/$ENVIRONMENT/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

When it's done, connect `kubectl` to your environment's cluster, replacing `<region-code>` with the region set in its `region.hcl`:
```bash
aws eks update-kubeconfig --region <region-code> --name $ENVIRONMENT-cluster
```

Then check the deployment by following [Connect to the Cluster](/docs/deployment/get-started/deploy-to-staging/#connect-to-the-cluster) and [Log In to ArgoCD](/docs/deployment/get-started/deploy-to-staging/#log-in-to-argocd), replacing `staging` with your environment's name in every hostname and secret name (e.g. `argocd.private.staging-2.<base_domain>` and `staging-2-argocd-password`). Skip the tests that follow: they only target `staging`.

The cluster's API endpoint is public, like the one of `staging`. To make it private, see [Disable the Public EKS Endpoint](/docs/security/improvements/#disable-the-public-eks-endpoint).

## Open a Pull Request and Merge

Follow [Release a Change to Production](/docs/deployment/release-a-change-to-production/) from [Open a Pull Request](/docs/deployment/release-a-change-to-production/#open-a-pull-request). Your change only adds folders and a CIDR, so the production plan should show nothing to add, change, or destroy.

## Keep the Environment Up to Date

CI and CD never apply your environment. On each release, make the same change in `live/<environment>/eks/stack/terragrunt.stack.hcl` as in the `staging` and `prod` stack files, whether you follow [Release an IaC Change](/docs/iac/release-an-iac-change/) or [Edit the Live Configuration](/docs/iac/edit-live-configuration/). Once the pull request is merged, apply it by hand, as in [Deploy the Environment](#deploy-the-environment).

## Destroy the Environment

Once you're done with the environment, destroy its stack to stop paying for it. Like for `staging`, disconnect from Tailscale first, by running `tailscale down` or with the button in the Tailscale client. Then run the following from the root of your live fork:
```bash
source .env
cd live/$ENVIRONMENT/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all destroy --non-interactive --no-stack-generate
```

Its hosted zone and Slack channels stay in place, so you can deploy it again later. Only the hosted zone is billed.

## Remove the Environment

To remove the environment for good, first [destroy its stack](#destroy-the-environment). Then destroy its two bootstrap pipelines, from the root of your live fork:
```bash
source .env
cd live/bootstrap/setup_dns/$ENVIRONMENT
terragrunt run --all destroy --non-interactive
cd ../../slack/channels/$ENVIRONMENT
terragrunt run --all destroy --non-interactive
```

Then:
1. Remove its NS records in your domain registrar. Left in place, they point your subdomain at name servers you no longer control, which can let someone else take it over.
2. Delete its state bucket, `tofu-state-<account-id>-<region>-<environment>`. It's versioned, so empty it from the [S3 console](https://console.aws.amazon.com/s3/buckets) first.
3. Delete `live/<environment>`, its two bootstrap folders, and its entry in `vpc_cidrs`, then merge the change, as in [Open a Pull Request and Merge](#open-a-pull-request-and-merge).
4. Remove its entry from `vpc_cidrs` in your catalog fork, apply the ACL again, and merge, as in [Approve the CIDR in Tailscale](#approve-the-cidr-in-tailscale).
