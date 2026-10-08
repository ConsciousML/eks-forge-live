# Troubleshooting

## Manually Removing a Terragrunt State

Sometimes you need to fully remove a module's state.

For example, when the state references resources that no longer exist.

This requires deleting the state file in S3 **and** the corresponding digest entry in DynamoDB. Doing only one will cause Tofu to error on the next run.

### Steps

**1. Delete the state file in S3:**

Go to the S3 bucket and delete the `.tfstate` file for the module, or use the CLI:

```bash
aws s3 rm s3://<bucket>/<path/to/module>/tofu.tfstate
```

**2. Find the stale DynamoDB entry:**

```bash
aws dynamodb scan \
  --table-name terragrunt_lock_table \
  --filter-expression "contains(LockID, :fragment)" \
  --expression-attribute-values '{":fragment": {"S": "<path/to/module>"}}' \
  --query "Items[*].LockID.S" \
  --output text
```

**3. Delete the digest entry** (the one ending in `-md5`):

```bash
aws dynamodb delete-item \
  --table-name terragrunt_lock_table \
  --key '{"LockID": {"S": "<bucket>/<path/to/module>/tofu.tfstate-md5"}}'
```

**4. Verify the state is gone:**

```bash
terragrunt init
terragrunt plan  # should show resources as "to be created"
```

## Can't Connect with Tailscale to Internal Endpoints on MacOS
MacOs doesn't automatically re-push DNS config.

The fix is to force Tailscale to re-apply DNS:
```bash
tailscale set --accept-dns=false && tailscale set --accept-dns=true
```

Or to flush the DNS cache:
```bash
sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder
```

## Can't Destroy `prod` Cluster
If the production cluster is created by [CD](../../.github/workflows/cd.yaml), our local IAM user is not added by default as a cluster administrator.

A temporary workaround is to assume the CI/CD role to be able to destroy the cluster.

We first modify the role to add our IAM user as a principal:
```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws iam update-assume-role-policy \
    --role-name gh-tg-live-eks-role \
    --policy-document "$(aws iam get-role --role-name gh-tg-live-eks-role \
      --query 'Role.AssumeRolePolicyDocument' --output json \
      | jq '.Statement += [{
          "Effect": "Allow",
          "Principal": {"AWS": "arn:aws:iam::${AWS_ACCOUNT_ID}:user/terragrunt"},
          "Action": "sts:AssumeRole"
        }]')"
```

Then, we are able to assume the role:
```bash
eval $(aws sts assume-role \
    --role-arn arn:aws:iam::${AWS_ACCOUNT_ID}:role/gh-tg-live-eks-role \
    --role-session-name local-destroy \
    --output json \
    | jq -r '.Credentials |
        "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport
  AWS_SESSION_TOKEN=\(.SessionToken)"')
```

Finally, we can destroy the `prod` infrastructure:
```bash
source .env
cd live/prod
terragrunt stack run destroy
```