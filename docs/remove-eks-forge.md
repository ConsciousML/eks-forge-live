{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
## Live Repository
### Destroy the Staging Stack
Destroying a stack removes its [Tailscale Connector](/docs/security/tailscale/#4-connector-and-split-dns), so you lose access to the cluster API. Before destroying, disconnect from Tailscale by running `tailscale down`, or with the button in the Tailscale client.

Then, run the following from the root of your live fork:
```bash
source .env
cd live/staging/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all destroy --non-interactive --no-stack-generate
```

### Destroy the Prod Stack
From the root of your live fork, run:
```bash
source .env
cd live/prod/eks/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all destroy --non-interactive --no-stack-generate
```

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
From the root of your live fork, destroy the [bootstrap pipelines](/docs/deployment/live-repository-setup/#bootstrap):
```bash
source .env
cd live/bootstrap
terragrunt run --all destroy --non-interactive
```

Finally, in your domain registrar, remove the NS records of the `staging` and `prod` subdomains. Left in place, they point your subdomains at name servers you no longer control, which can let someone else take them over.
