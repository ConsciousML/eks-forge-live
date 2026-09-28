{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### AWS GitHub Actions Authentication
This pipeline lets your live fork's CI/CD authenticate with AWS. It reuses the OIDC provider created from your catalog fork.

From the root of your live fork, run:
```bash
source .env
cd live/bootstrap/aws_gh_actions_auth
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

For more information, read the [AWS GitHub Actions Authentication quickstart](/docs/quickstart/bootstrap/aws_gh_actions_auth/).
