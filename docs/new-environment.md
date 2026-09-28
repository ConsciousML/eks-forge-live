# Create a New Environment

Changes span both the catalog and live repos. Three steps are hard prerequisites for the final EKS deploy: the Tailscale ACL must include the new VPC CIDR before the connector can route traffic, and the public Route53 hosted zone must exist before ACM can validate TLS certificates.

> **Deploying a dev environment?** Those live in the catalog repo. Follow the [catalog repo new environment guide](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/docs/new-environment.md) instead.

The example below adds a `pre-staging` environment.

## Prerequisites

Complete [Getting Started](../README.md#getting-started) in full. You need at least one working environment (`staging` or `prod`) before adding another.

## Steps

### 1. Add the CIDR to the catalog

In the catalog repo, add the new environment to `pipelines/network.hcl`:

```hcl
locals {
  vpc_cidrs = {
    prod        = "10.0.0.0/16"
    staging     = "10.1.0.0/16"
    pre-staging = "10.2.0.0/16"  # new
  }
}
```

Pick the next available `/16` block. Check both `pipelines/network.hcl` in the catalog repo and `live/network.hcl` in this repo for CIDRs already in use.

### 2. Re-run the Tailscale bootstrap

Re-apply the Tailscale bootstrap to register the new CIDR in `autoApprovers`. See the [Tailscale bootstrap README](../live/bootstrap/tailscale/README.md) for prerequisites and commands.

```bash
source .env
cd live/bootstrap/tailscale
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

### 3. Add the CIDR to the live repo

Add the matching entry to `live/network.hcl`:

```hcl
locals {
  vpc_cidrs = {
    prod        = "10.0.0.0/16"
    staging     = "10.1.0.0/16"
    pre-staging = "10.2.0.0/16"  # new
  }
}
```

### 4. Run the DNS bootstrap

Copy the staging DNS bootstrap directory:

```bash
cp -r live/bootstrap/setup_dns/staging live/bootstrap/setup_dns/pre-staging
```

Edit `live/bootstrap/setup_dns/pre-staging/environment.hcl`:

```hcl
locals {
  environment = "pre-staging"
}
```

Then apply it and delegate the NS records at your registrar. See the [DNS bootstrap README](../live/bootstrap/setup_dns/README.md) for the full deploy and delegation steps.

### 5. Create the environment directory

```bash
cp -r live/staging live/pre-staging
```

Update `live/pre-staging/environment.hcl`:

```hcl
locals {
  environment = "pre-staging"
}
```

Update `live/pre-staging/region.hcl` if the new environment targets a different AWS region.

### 6. Revisit EC2 quotas

The new environment's node groups add to the account's total vCPU usage. Check whether the catalog repo's [`aws_service_quotas` bootstrap](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/pipelines/bootstrap/aws_service_quotas/README.md) still covers it before deploying.

### 7. Deploy the EKS stack

```bash
source .env
cd live/pre-staging/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```
