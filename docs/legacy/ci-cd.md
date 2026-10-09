# Continuous Integration and Deployment (CI/CD)

## Overview

The [CI](../../.github/workflows/ci.yaml) and [CD](../../.github/workflows/cd.yaml) workflows automate infrastructure validation, testing, and deployment on every pull request and merge.

## Features

- Validates HCL formatting on every PR
- Plans staging and prod in parallel
- Gates on a required `run-terratest` or `skip-terratest` label before proceeding
- Runs Terratest infrastructure tests on staging and cleans up automatically
- Comments the production plan artifact on the PR
- Auto-deploys to production on merge to `main`

For details on each step, see [How CI/CD Works](#how-cicd-works).

## Prerequisites
Perform the [quickstart](../../README.md#getting-started) up to `Authenticate with AWS` (included).

Then, run the [bootstrap pipelines](../../README.md#run-the-bootstrap-pipelines) once per repository.

## Using the CI/CD (Development Workflow)

> **Caution**: If you will need to run `terragrunt destroy` or any K8s operation locally against `prod` after CD deploys, configure your IAM access entry **before** opening the PR, see [Local Access After CD Deployment](#local-access-after-cd-deployment).

1. Create a branch with your infrastructure changes:
   ```bash
   git checkout -b feature/update-instance-size
   ```

2. Make changes into the Terraform code, units, and stacks in the catalog repository by following its [development workflow](https://github.com/ConsciousML/eks-forge-catalog/blob/main/docs/development.md).

3. Next, bump the catalog version and align the live stack. For example, in `live/staging/eks/stack/terragrunt.stack.hcl`:
```hcl
locals {
  version_catalog = "v0.0.4" # bump to the new catalog tag
  # adopt any new helm chart version locals from the catalog pipeline
}
```

4. Push your code.

5. Open a pull request. The CI pipeline runs automatically.

6. Review the CI results:
   - Check that all validation passes. If not, implement a fix, and go back to 4.
   - Download and review the **production plan artifact** (linked in PR comment)
   - The plan shows exactly what will be created, modified, or destroyed

7. Add a label — **required before CI can complete**:
   - `run-terratest`: deploys real infrastructure to staging, validates end-to-end, and cleans up automatically — use this before merging significant changes
   - `skip-terratest`: skips the staging deployment

8. Review and merge. Add the `skip-cd` label if you want to skip 9.

9. CD automatically deploys to production after merge completes.

## How CI/CD Works

### Continuous Integration (CI)

Runs automatically on every pull request to `main` and is composed of eight jobs:

#### 1. Draft PR Check
Fails immediately if the PR is in draft mode — CI does not run on draft PRs.

#### 2. HCL Format Check
Validates that all Terragrunt (`.hcl`) files are properly formatted.

#### 3. Validate & Plan
Runs in parallel across **staging** and **prod** environments:
- Generates stack configurations
- Initializes Terragrunt with backend bootstrapping
- Validates Terraform/OpenTofu syntax
- Creates infrastructure plans showing what will change

For the **production environment**, the plan output is converted to HTML and uploaded as a downloadable artifact for review.

A temporary Tailscale OAuth client is created for this job and revoked by the **Revoke Plan OAuth** cleanup job that always runs afterward.

#### 4. Terratest Label Gate
After validate & plan, CI checks that the PR has exactly one of two labels before proceeding. **This is a hard gate — CI fails if neither label is present:**
- `run-terratest`: infrastructure tests will run
- `skip-terratest`: infrastructure tests will be skipped

#### 5. Terratest
See the [Terratest guide](../../tests/README.md) for details on what is tested and how to extend it.

Runs only when the `run-terratest` label is present:
- Deploys the AWS infrastructure to the staging environment
- Runs Go-based validation tests
- Automatically destroys all test resources
- A temporary Tailscale OAuth client is created for the duration of the test and revoked by the **Revoke OAuth** cleanup job that always runs afterward

#### 6. Revoke OAuth (cleanup)
Two cleanup jobs always run after the plan and terratest phases to revoke any temporary Tailscale OAuth clients, even on failure. This ensures no credentials are left behind.

#### 7. Comment on PR
Posts a comment with:
- Link to the production plan artifact
- Commit SHA that was tested
- Warning that merging will apply changes to production

### Continuous Deployment (CD)

Runs automatically when a PR is **merged to `main`** and is composed of three jobs:

1. **Check skip-cd**: looks up the PR for the merged commit and checks for the `skip-cd` label. If the label is present, or no PR is found, deployment is skipped as a safety measure.
2. **Apply**: ensures the EC2 Spot service-linked role exists, then runs `terragrunt run --all apply` against `prod`.
3. **Revoke OAuth**: revokes the temporary Tailscale OAuth client created during apply, even on failure.

**Important**: CD automatically applies to production. Always review the production plan from CI before merging. If you want to skip the deployment, add the `skip-cd` label before merging the PR.

## Local Access After CD Deployment

The bootstrap automatically registers the IAM identity used to run it as a cluster admin. It stores that ARN as the `EKS_LOCAL_ADMIN_ARN` GitHub Actions secret, and CD injects it on every apply so the access entry is always in sync.

If a second developer needs local prod access, add them as a separate entry in the [`access_entries` block](../../live/prod/eks/stack/terragrunt.stack.hcl) of the cluster unit.
