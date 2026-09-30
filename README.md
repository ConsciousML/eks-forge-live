# Terragrunt Template Live AWS

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Release](https://img.shields.io/github/release/ConsciousML/terragrunt-template-live-eks.svg?style=flat)]()
[![CI](https://github.com/ConsciousML/terragrunt-template-live-eks/actions/workflows/ci.yaml/badge.svg)](https://github.com/ConsciousML/terragrunt-template-live-eks/actions/workflows/ci.yaml)
[![CD](https://github.com/ConsciousML/terragrunt-template-live-eks/actions/workflows/cd.yaml/badge.svg)](https://github.com/ConsciousML/terragrunt-template-live-eks/actions/workflows/cd.yaml)
[![PR's Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat)](http://makeapullrequest.com)

A prod-ready live Terragrunt repository for deploying [EKS](https://aws.amazon.com/eks/) clusters across `staging` and `prod` with automated CI/CD.

The [EKS Cluster Stack](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/units/eks/README.md) supports:
- Persistent storage via EBS-backed `PersistentVolumeClaim`s
- Cluster and workload metrics via Prometheus, Alertmanager, and Grafana
- Workload resource-sizing recommendations via the VPA recommender and Goldilocks
- Log aggregation via Loki
- Public and private traffic routing via ALB and Gateway API
- Automated DNS and TLS termination
- Secrets synced from AWS Secrets Manager
- GitOps via ArgoCD and the App of Apps pattern
- VPN access via Tailscale
- Node autoscaling via Karpenter
- Pod-to-pod network flow visibility via Cilium and Hubble

## Catalog vs Live Infrastructure

This toolkit uses two template repositories:
- **Catalog repository**: Defines **what** can be deployed (reusable components: [modules, units, and stacks](https://github.com/ConsciousML/terragrunt-template-catalog-eks))
- **This repository** (live): Defines **where** and **how** catalog components are deployed in `staging` and `prod` environments with CI/CD

You're new to Terragrunt best practices? Read [Gruntwork's official production patterns](https://github.com/gruntwork-io/terragrunt-infrastructure-live-example) to get the foundations required to use this toolkit.

## What's Inside
- Multi-environment IaC support: build EKS cluster across `staging`, and `prod`.
- [CI](.github/workflows/ci.yaml) (on PR): Runs `terragrunt plan` on each environment, uploads output plan to PR, deploys on the staging environment, runs tests, and destroys.
- [CD](.github/workflows/cd.yaml) (on push `main`): Automatically deploys on `prod`
- [Bootstrap pipelines](live/bootstrap/): one-time setup required before deploying the EKS stack.

## Getting Started

Follow the [deployment documentation](https://eks-forge.readthedocs.io/latest/docs/deployment/get-started/).

### Deploy a Staging EKS Cluster
Deploy the [EKS Cluster Stack](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/units/eks/README.md):

```bash
source .env
cd live/staging/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Go into the AWS console and check that your resources have been created.

After around 15 min, your `staging` EKS cluster will be created.

Connect `kubectl` to your EKS cluster by creating a `kubeconfig` (replace `<region-code>` and `<cluster-name>`):
```bash
aws eks update-kubeconfig --region <region-code> --name <cluster-name>
```

Next, verify `kubectl` is connected:
```
kubectl get pods -n kube-system
```

You should see an output similar to:
```text
NAME                           READY   STATUS    RESTARTS   AGE
aws-node-59ld8                 2/2     Running   0          41m
coredns-845b86cddf-pg8hk       1/1     Running   0          40m
eks-pod-identity-agent-9pq6k   1/1     Running   0          41m
...
```

### Log in to ArgoCD

ArgoCD is only reachable with the Tailscale Client running. Make sure you have completed the [Tailscale prerequisites](live/bootstrap/tailscale/README.md#prerequisites) before proceeding.

The ArgoCD host is `argocd.private.staging.<base_domain>` (replace `<base_domain>` with the value from `live/dns.hcl`, e.g. `argocd.private.staging.axelmendoza.com`).

**Web UI**: Open `https://argocd.private.staging.<base_domain>` in your browser and log in with username `admin`. Retrieve the password with:
```bash
aws secretsmanager get-secret-value \
  --secret-id staging-argocd-password \
  --query SecretString \
  --output text | jq -r .plaintext
```

**CLI**: Log in directly in one command:
```bash
argocd login argocd.private.staging.<base_domain> \
  --username admin \
  --password $(aws secretsmanager get-secret-value \
    --secret-id staging-argocd-password \
    --query SecretString \
    --output text | jq -r .plaintext)
```

### Disable the Public EKS Endpoint

Logging into ArgoCD over Tailscale confirms the Tailscale Connector is routing into the VPC. For improved security, set `endpoint_public_access` to `false` in the [staging](live/staging/eks/stack/terragrunt.stack.hcl) or [prod](live/prod/eks/stack/terragrunt.stack.hcl) EKS stack, then re-apply just the `cluster` unit (cwd in `live/staging/eks/stack` or `live/prod/eks/stack`):

```bash
cd .terragrunt-stack/eks/cluster
terragrunt apply --non-interactive
```

From this point on, `kubectl` and the AWS CLI can only reach the API server while connected to Tailscale.

### Monitoring

Grafana, Prometheus, and Alertmanager are only reachable via Tailscale, same as ArgoCD. See [Accessing the UIs](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/docs/monitoring.md#accessing-the-uis) for UI URLs, what each tool is for, and how Alertmanager routes alerts to Slack.

### Access the Podinfo App

Open `https://podinfo.public.staging.<base_domain>` in your browser. No login required.

Apps are deployed using the [App of Apps](https://github.com/ConsciousML/argocd-app-of-apps-template) pattern: a single ArgoCD Application bootstraps all child apps from that repository.

### Destroy the Infrastructure

Destroying the [App of Apps unit](https://github.com/ConsciousML/terragrunt-template-catalog-eks/tree/main/units/eks/addons/argocd/app_of_apps) removes the Tailscale Connector, which is what routes API server traffic into the private endpoint. Once it's gone, you lose access to the cluster API unless you've already restored the public endpoint.

**Caution**: Before destroying the stack:
1. Set `endpoint_public_access` back to `true` (if you disabled the public EKS endpoint) and apply the `cluster` unit first
2. Run `tailscale down`

Finally, cleanup by destroying the infrastructure (cwd in `live/staging/eks/stack`, or see [Can't Destroy `prod` Cluster](docs/troubleshoot.md#cant-destroy-prod-cluster) for prod):

```bash
terragrunt run --all destroy --non-interactive --no-stack-generate
```

## Extend this Repository
Follow the [development workflow guide](docs/ci-cd.md#using-the-cicd-development-workflow).

## CI/CD Pipelines

### CI (Pull Requests)
- Validates HCL formatting
- Runs `terragrunt plan` on `staging` and `prod` in parallel
- Runs infrastructure tests with Terratest
- Comments on PR with production plan artifact

### CD (Merge to main)
- Automatically deploys to the production environment (i.e `prod`).

See the [CI/CD workflow guide](docs/ci-cd.md) for detailed setup instructions and usage.

## Testing

See the [Terratest guide](tests/README.md) for running and writing infrastructure tests.

### Pre-commit Setup (recommended)
We use a more efficient framework than [pre-commit](https://github.com/pre-commit/pre-commit) called [prek](https://github.com/j178/prek).

Wire hooks automatically into git automatically:
```bash
prek install
```

Run hooks on demand:
```bash
prek run
```

## Create a New Environment

See the [new environment guide](docs/new-environment.md) for the full sequence of steps.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for details.