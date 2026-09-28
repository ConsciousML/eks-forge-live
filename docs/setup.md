{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
# Live Repository Setup

In this tutorial, you'll fork the [live repository](https://github.com/ConsciousML/terragrunt-template-live-eks), install its CLI tools, and point it at your catalog fork.

## Prerequisites
Complete the [quickstart](/docs/quickstart/) first. Live reuses its [prerequisites](/docs/quickstart/prerequisites/), bootstrap resources, and catalog fork.

## Fork the Live Repository
The live repository deploys the [catalog stacks](/docs/architecture/) in the `staging` and `prod` environments.
Like the catalog, it's meant to be forked and extended.

Follow the same steps as when you [forked the catalog](/docs/quickstart/installation/#fork-the-eks-forge-catalog). First, [create an empty repository](https://github.com/new) on GitHub, private or public. Leave the README, `.gitignore`, and license options unset.

:::warning
Create it under the same GitHub owner (user or organization) as your catalog fork. The [bootstrap pipelines](#bootstrap) write GitHub secrets and deploy keys under the catalog fork's owner.
:::

Then, set your GitHub owner (user or organization) and the name of the repository you created, by replacing the `<...>`:
```bash
export GITHUB_OWNER=<your-github-owner>
export LIVE_REPO_NAME=<your-live-repo-name>
```

Clone the live repository and push it to your repository:
```bash
git clone https://github.com/ConsciousML/terragrunt-template-live-eks.git $LIVE_REPO_NAME
cd $LIVE_REPO_NAME
git remote set-url origin git@github.com:$GITHUB_OWNER/$LIVE_REPO_NAME.git
git push origin main
git push origin --tags
```

## Install the CLI Tools
From the root of your live fork, install the tools pinned in [`mise.toml`](../mise.toml) and [`mise.local.toml`](../mise.local.toml):
```bash
mise trust
mise install
```

## Live Configuration
Live reads `.hcl` configuration files under [`live/`](../live/), like the catalog's `pipelines/`. They point to the catalog's [units](/docs/iac/#units), so `staging` and `prod` use the same components you deployed in [`dev`](/docs/iac/#dev).

In [`live/github.hcl`](../live/github.hcl), set these four values and leave the others as is:
```hcl
locals {
  github_owner_catalog         = "<your-github-username-or-org-name-where-your-catalog-fork-is>"
  github_owner_live            = "<your-github-username-or-org-name-where-your-live-fork-is>"
  github_repo_name_catalog     = "<your-catalog-repo-name>"
  github_repo_name_live        = "<your-live-repo-name>"
  ...
}
```
This makes your live fork use the modules and units of your catalog fork instead of the original catalog repository.

Each [environment](/docs/iac/#environments) sets its AWS region in its own `region.hcl` file:
- [`live/staging/region.hcl`](../live/staging/region.hcl)
- [`live/prod/region.hcl`](../live/prod/region.hcl)
- [`live/bootstrap/region.hcl`](../live/bootstrap/region.hcl)

Like when you [configured the catalog](/docs/quickstart/configuration/#catalog-configuration), set `region` and `azs` in the `staging` and `prod` files:
```hcl
locals {
  region = "us-east-1"
  azs    = ["us-east-1a", "us-east-1b", "us-east-1c"]
}
```
The `bootstrap` file has no `azs`, so you only need to set `region`.

You can also leave them as is if you plan to use `us-east-1`.

## Bootstrap
:::warning
These pipelines need to run only once per live fork before deploying to [`staging`](/docs/deployment/deploy-to-staging/) and [`prod`](/docs/deployment/promote-to-production/).
:::

You'll run the bootstrap pipelines from your live fork, as you did from your [catalog fork](/docs/quickstart/installation/#fork-the-eks-forge-catalog) in the [quickstart bootstrap](/docs/quickstart/bootstrap/).

They read the same environment variables as the catalog. Copy your catalog `.env` to the root of your live fork:
```bash
cp <path-to-your-catalog-fork>/.env .env
```
