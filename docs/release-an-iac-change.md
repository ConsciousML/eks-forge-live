{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}

# How to Release an IaC Change

This guide shows you how to ship the changes merged in your [catalog fork](/docs/quickstart/installation/#fork-the-eks-forge-catalog) to [`staging`](/docs/iac/#staging) and [`prod`](/docs/iac/#prod), and align your [live fork](/docs/deployment/get-started/live-repository-setup/#fork-the-live-repository) with what changed in the catalog since your last release. It's one of the steps of [Release a Change to Production](/docs/deployment/release-a-change-to-production/), and assumes you've created a branch in your live fork, as in [Create a Live Branch](/docs/deployment/release-a-change-to-production/#create-a-live-branch).

## Tag the Catalog Fork

From the root of your catalog fork, tag `main` and push the tag, replacing `<new-tag>` with the next version after your fork's latest tag (e.g. `v0.2.0`):
```bash
git checkout main
git pull origin main
git tag <new-tag>
git push origin <new-tag>
```

## Review the Catalog Changes

Your current tag is the `version_catalog` at the top of [`live/prod/eks/stack/terragrunt.stack.hcl`](../live/prod/eks/stack/terragrunt.stack.hcl):
```hcl
locals {
  version_catalog = "v0.1.9.1"
  ...
}
```

From the root of your catalog fork, list the files that changed between your current tag and the new one, replacing `<old-tag>` and `<new-tag>`:
```bash
git fetch --tags
git diff --stat <old-tag> <new-tag> -- mise.toml .env.example .github/ pipelines/
```

Then read the full diff:
```bash
git diff <old-tag> <new-tag> -- mise.toml .env.example .github/ pipelines/
```

The sections below walk through this diff, one group of files at a time.

## Align Tools and Environment Variables

If the catalog changed a tool version in `mise.toml`, set the same version in your live `mise.toml`, so CI and your local runs use the tools the catalog was tested with. For example:
```toml
[tools]
terragrunt = "1.1.3" # match the catalog's version
```

Then install the new versions locally:
```bash
mise install
```

Skip tools that only exist in the catalog's `mise.toml`, such as `tflint` and `trivy`. They serve catalog development, not live.

If the catalog added a variable to `.env.example`, check what uses it in the [Environment Variables](/docs/reference/environment_variable/) reference. Skip it if only `dev` or an account-level pipeline that already ran from your catalog fork uses it, such as `APP_OF_APPS_BRANCH` or `BILLING_ANOMALY_MONITOR_ARN`. Otherwise, add it to your live `.env.example` and set it in your `.env`. Point its comment at the variable's entry in the reference, like the existing ones:
```bash
# See https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/docs/environment-variables.md#slack_bot_token
export SLACK_BOT_TOKEN=
```

If CI or CD needs the variable, create a [bootstrap pipeline](/docs/quickstart/bootstrap/) that writes it as a GitHub Actions secret, or update an existing one. Then pass the secret in the `env` of every step that runs Terragrunt, in [`.github/workflows/ci.yaml`](../.github/workflows/ci.yaml) and [`.github/workflows/cd.yaml`](../.github/workflows/cd.yaml):
```yaml
env:
  SLACK_BOT_TOKEN: ${{ secrets.SLACK_BOT_TOKEN }}
```

## Align the CI Setup

The catalog's [`ci.yaml`](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/.github/workflows/ci.yaml) runs checks specific to the catalog, such as lock files and module docs, so don't port its jobs. What both repos share is the setup action that installs the tools and authenticates to AWS. If the catalog changed it, port the change to your live [`.github/actions/setup/action.yml`](../.github/actions/setup/action.yml), keeping live's own settings, such as the longer `role-duration-seconds` Terratest needs.

## Update the Bootstrap Pipelines

Set `version` to the new tag at the top of every `terragrunt.stack.hcl` under `live/bootstrap/`, including the nested ones such as `setup_dns/prod/stack/`, replacing `<new-tag>`:
```hcl
locals {
  version = "<new-tag>"
  ...
}
```

If the diff touches `pipelines/bootstrap/`, port the changes to `live/bootstrap/`. Where the catalog has one stack per environment, as under `setup_dns/` and `slack/channels/`, its `dev/` and `ci/` folders correspond to live's `staging/` and `prod/`, so port a change to both:
- **New pipeline**: read its page under [Bootstrap Pipelines](/docs/quickstart/bootstrap/) first. Skip it if it's account-level, like [AWS Service Quotas](/docs/quickstart/bootstrap/aws_service_quotas), since it already ran from your catalog fork, or if it's marked dev-only or CI-only.
- **Changed pipeline**: carry over its restructured stacks, renamed units, and changed `values`.

CI and CD never apply the bootstrap pipelines, so a missed change drifts silently. From the root of your live fork, plan all of them at once:
```bash
source .env
cd live/bootstrap
terragrunt run --all plan
```

:::warning
This apply runs before your pull request is reviewed, because CI needs what the bootstrap pipelines create, such as GitHub Actions secrets. Some are shared by `staging` and `prod`, so a mistake here reaches `prod`. Read the plan carefully before applying.
:::

If the plan shows changes, apply them:
```bash
terragrunt run --all apply --non-interactive
```

## Update the Shared Configuration

If the diff touches a shared `.hcl` file under `pipelines/`, such as `dns.hcl` or `domains.hcl`, port the change to its live counterpart. The [HCL Configuration](/docs/reference/hcl_configuration/#layout) reference maps each catalog file to its live counterpart. Watch for renamed `locals`, not just added ones: every stack file that reads the old name breaks.

## Update the EKS Stacks

Set `version_catalog` to the new tag at the top of both [`live/staging/eks/stack/terragrunt.stack.hcl`](../live/staging/eks/stack/terragrunt.stack.hcl) and [`live/prod/eks/stack/terragrunt.stack.hcl`](../live/prod/eks/stack/terragrunt.stack.hcl), replacing `<new-tag>`:
```hcl
locals {
  version_catalog = "<new-tag>"
  ...
}
```

Then apply the diff of [`pipelines/dev/eks/stack/terragrunt.stack.hcl`](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/pipelines/dev/eks/stack/terragrunt.stack.hcl) to both stack files, following the sections below for each added, removed, or changed unit.

Don't adopt a value marked `# DEV:`, it only applies to [`dev`](/docs/iac/#dev). Keep live's own lines, marked `# STAGING:` or `# PROD:`, instead. For example, `dev` disables control plane logging, while `prod` keeps it:
```hcl
# pipelines/dev/eks/stack/terragrunt.stack.hcl (catalog)
# DEV: control plane logging disabled to cut CloudWatch costs, do not port this to
# staging/prod, re-enable there.
enabled_log_types = []

# live/prod/eks/stack/terragrunt.stack.hcl (live)
# PROD: dev disables control plane logging entirely to cut costs, prod enables "api"
enabled_log_types = ["api"]
```

Which values are marked can change between tags, so re-read the `# DEV:` comments on every release.

### Added Units

Copy the unit's `unit` block, and rewrite its `source` from the local path to your catalog fork, pinned to `version_catalog`:
```hcl
# dev
source = "${get_repo_root()}/units/<unit>"
# live
source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/<unit>?ref=${local.version_catalog}"
```

### Removed Units

Delete the unit's `unit` block, and note its `path` for later. If other units depend on it, carry over the changes that drop those dependencies in the same release.

CD doesn't destroy a unit whose block is gone, so its resources stay in `prod` and keep being billed. You destroy it once CD has applied the release, see [Destroy Removed Units](#destroy-removed-units).

### Changed Units

Carry over the unit's new or changed `values`. If a `version_*` local changed, set the same module or chart version.

Then continue at [Roll Out to Staging and Prod](/docs/deployment/release-a-change-to-production/#roll-out-to-staging-and-prod).

## Destroy Removed Units

If your release removed units, destroy them in `prod` once CD succeeds. At that point, no unit left in `prod` depends on them.

From the root of your live fork, check out the commit on `main` just before your merge, where the stack still declares them. Then destroy each removed unit, replacing `<path>` with the unit's `path` you noted:
```bash
source .env
cd live/prod/eks/stack
terragrunt stack clean
terragrunt stack generate
cd .terragrunt-stack/<path>
terragrunt destroy
```

Then return to `main`:
```bash
git checkout main
```
