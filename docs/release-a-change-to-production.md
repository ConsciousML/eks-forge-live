{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

# How to Release a Change to Production

This guide shows you how to ship a change to [`staging`](/docs/iac/#staging) and [`prod`](/docs/iac/#prod).

`prod` only changes through a pull request in your [live fork](/docs/deployment/get-started/live-repository-setup/#fork-the-live-repository). Your catalog and app of apps forks only produce the tags it pins.

## Develop and Test in Dev

Depending on what you changed, first follow:
- **A unit in your catalog fork**: [Add or Edit a Unit](/docs/iac/add-a-unit/) or [Remove a Unit](/docs/iac/remove-a-unit/).
- **An app in your app of apps fork**: [Add, Edit, or Remove an App](/docs/applications/add-edit-or-remove-an-app/).
- **Only the live configuration**: skip to [Create a Live Branch](#create-a-live-branch).

## Create a Live Branch

From the root of your live fork, create a branch, replacing `<branch>`:
```bash
git checkout -b <branch>
```

## Update the Live Fork

On this branch, follow every guide that fits your change. They all go into the same pull request:
- **You merged a change in your catalog fork**: [Release an IaC Change](/docs/iac/release-an-iac-change/).
- **You merged a change in your app of apps fork**: [Release an App Change](/docs/applications/release-an-app-change/).
- **You're changing the live configuration**: [Edit the Live Configuration](/docs/iac/edit-live-configuration/).

If your change added or removed an [`appParams`](/docs/applications/how-the-app-of-apps-works/#appparams-injection) key, release both forks in this same pull request. The `argocd_app_of_apps` unit applies `version_catalog` and `app_of_apps_target_revision` at once, and `apps/values.schema.json` rejects any `appParams` key it doesn't list.

## Roll Out to Staging and Prod

From the root of your live fork, commit your changes and push the branch, replacing `<message>` and `<branch>`:
```bash
git add -A
git commit -m "<message>" # e.g. "feat: raise critical nodepool cpu limit"
git push -u origin <branch>
```

Open a pull request with the label that fits your change:

<Tabs groupId="terratest-label">
<TabItem value="run" label="run-terratest">

Deploys `staging`, tests it end to end, and destroys it. Use it by default:
```bash
gh pr create --title "<message>" --body "<description>" --label run-terratest
```

</TabItem>
<TabItem value="skip" label="skip-terratest">

Skips the `staging` tests. Use it only if you changed nothing but docs:
```bash
gh pr create --title "<message>" --body "<description>" --label skip-terratest
```

</TabItem>
</Tabs>

See [CI/CD](/docs/ci-cd/) for each job.

Before merging, download the production plan from the **Production Plan Available** comment CI posts on your pull request, and check what it changes in `prod`, see [Watch CI](/docs/deployment/get-started/promote-to-production/#watch-ci). If a job fails, see [Troubleshoot Live CI](/docs/ci-cd/per-repository/troubleshoot-live-ci/). When every job is green, merge:
```bash
gh pr merge --merge
```

Merging to `main` triggers CD, which applies your change to `prod`. See [Deploy to Production](/docs/deployment/get-started/promote-to-production/#deploy-to-production) to check the deployment.

## Clean Up After the Rollout

Once CD succeeds:
- If you removed a unit, follow [Destroy Removed Units](/docs/iac/release-an-iac-change/#destroy-removed-units).
- If you removed an app, follow [Delete a Removed App's Namespace](/docs/applications/release-an-app-change/#delete-a-removed-apps-namespace).
