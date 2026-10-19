{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
## Live Repository
### Destroy the Staging Stack
Destroying a stack removes its [Tailscale Connector](/docs/networking/tailscale/#4-connector-and-split-dns), so you lose access to the cluster API. Before destroying, disconnect from Tailscale by running `tailscale down`, or with the button in the Tailscale client.

Then, run the following from the root of your live fork:
```bash
source .env
cd live/staging/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all destroy --non-interactive --no-stack-generate
```

If you added an environment with [Add a Staging Environment](/docs/iac/add-a-staging-environment/), destroy its stack too, as in [Destroy the Environment](/docs/iac/add-a-staging-environment/#destroy-the-environment).

### Destroy the Prod Stack
`prod` sets `force_destroy = false` on its Loki buckets, so an accidental destroy doesn't lose your logs. As a result, the destroy fails while these buckets hold objects.

In [`live/prod/eks/stack/terragrunt.stack.hcl`](../live/prod/eks/stack/terragrunt.stack.hcl), set `force_destroy = true` in the `loki_s3_chunks` and `loki_s3_ruler` blocks.

Then, from the root of your live fork, apply the two bucket units so the buckets take the new value:
```bash
source .env
cd live/prod/eks/stack
terragrunt stack clean
terragrunt stack generate
(cd .terragrunt-stack/eks/addons/loki/s3/chunks && terragrunt apply -auto-approve)
(cd .terragrunt-stack/eks/addons/loki/s3/ruler && terragrunt apply -auto-approve)
```

Finally, destroy the stack from the same directory:
```bash
terragrunt run --all destroy --non-interactive --no-stack-generate
```

If you plan to deploy EKS Forge again, restore the file from the root of your live fork, so `prod` protects its logs again:
```bash
git checkout live/prod/eks/stack/terragrunt.stack.hcl
```

If the destroy ends with an error on a Loki bucket unit, see [The Destroy Fails on a Loki Bucket](/docs/troubleshooting/iac/#the-destroy-fails-on-a-loki-bucket).

### Delete Leftover EBS Volumes
`prod` retains the volumes of Prometheus, Alertmanager, and Loki when their pods are deleted, so an accidental deletion doesn't lose your metrics and logs. As a result, these volumes outlive the `prod` stack and keep being billed.

Set the region you set in [`live/prod/region.hcl`](../live/prod/region.hcl), by replacing `<region-code>`:
```bash
export AWS_REGION=<region-code>
```

List the EBS volumes left over from your clusters:
```bash
aws ec2 describe-volumes \
  --filters Name=status,Values=available Name=tag:ebs.csi.aws.com/cluster,Values=true \
  --query 'Volumes[].{ID:VolumeId,PVC:Tags[?Key==`kubernetes.io/created-for/pvc/name`]|[0].Value,Size:Size}' \
  --output table
```

:::warning
This lists every unattached volume created by an EKS cluster in the region, not only EKS Forge's. If other clusters run in your AWS account, check the `PVC` column before deleting.
:::

Then, delete all of them:
```bash
for volume_id in $(aws ec2 describe-volumes \
  --filters Name=status,Values=available Name=tag:ebs.csi.aws.com/cluster,Values=true \
  --query 'Volumes[].VolumeId' \
  --output text); do
  aws ec2 delete-volume --volume-id "$volume_id"
done
```

### Destroy the Live Bootstrap
From the root of your live fork, destroy the [bootstrap pipelines](/docs/deployment/get-started/live-repository-setup/#bootstrap), except the state KMS key. The other states need it to decrypt, and its `prevent_destroy` would fail the run:
```bash
source .env
cd live/bootstrap
terragrunt run --all destroy --non-interactive --filter '!./terraform_state_encryption/**'
```

Then, schedule the deletion of the key:
```bash
aws kms schedule-key-deletion --key-id $(aws kms describe-key --key-id alias/bootstrap-live-eks-tofu-state --query KeyMetadata.KeyId --output text)
```

AWS deletes it after a waiting period, and you can restore it until then (see [Deletion](/docs/reference/terraform_modules/kms_key/#deletion)).

Finally, in your domain registrar, remove the NS records of the `staging` and `prod` subdomains, and of any environment you added. Left in place, they point your subdomains at name servers you no longer control, which can let someone else take them over.
