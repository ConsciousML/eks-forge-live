{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### PagerDuty
This pipeline creates the `staging` and `prod` PagerDuty services Alertmanager pages through, stores their integration keys in AWS Secrets Manager, and adds your PagerDuty service region to your live fork's GitHub secrets. Only `prod` pages, `staging` alerts reach Slack only.

It reads `PAGERDUTY_TOKEN` and `PAGERDUTY_SERVICE_REGION` from your `.env`, as described in the [Environment Variables](/docs/reference/environment_variable/#pagerduty_token-and-pagerduty_service_region) reference.

From the root of your live fork, run:
```bash
source .env
cd live/bootstrap/pagerduty
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Then, check that the pipeline added the region to your live fork's GitHub secrets:
```bash
gh secret list
```

You should see `PAGERDUTY_SERVICE_REGION`. It holds `us` for a US account, since a GitHub secret can't be empty.
