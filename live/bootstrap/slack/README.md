{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### Slack
This pipeline adds your Slack bot token to your live fork's GitHub secrets and creates the `staging` and `prod` alert channels.

From the root of your live fork, run:
```bash
source .env
cd live/bootstrap/slack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
```

Then, check that the bootstrap pipelines added their secrets to your live fork:
```bash
gh secret list
```

You should see secrets from each pipeline, including `AWS_ROLE_ARN`, `TS_OAUTH_CLIENT_ID`, and `SLACK_BOT_TOKEN`.

Finally, join the `staging-` and `prod-` prefixed channels, as you did for the `dev-` ones in [Slack Bootstrap](/docs/quickstart/bootstrap/slack/) (see [`live/bootstrap/slack/channels.hcl`](channels.hcl) for the base names).
