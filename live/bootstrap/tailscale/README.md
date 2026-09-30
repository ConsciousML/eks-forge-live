{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### Tailscale
This pipeline lets your live fork's CI authenticate to Tailscale. It reuses the tailnet ACL applied from your catalog fork.

From the root of your live fork, run:
```bash
source .env
cd live/bootstrap/tailscale
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

For more information, read [Tailscale Bootstrap](/docs/quickstart/bootstrap/tailscale/).
