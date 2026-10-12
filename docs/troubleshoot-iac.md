{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
## The Destroy Fails on a Loki Bucket

The destroy of `prod` ends with an error on the `eks/addons/loki/s3/chunks` unit. `prod` sets `force_destroy = false` on its Loki buckets, and the bucket still held objects when the destroy reached it.

Empty the bucket, with `AWS_REGION` set to the region of [`live/prod/region.hcl`](../live/prod/region.hcl):
```bash
aws s3 rm "s3://prod-loki-chunks-$(aws sts get-caller-identity --query Account --output text)-$AWS_REGION" --recursive
```

Then destroy the unit again, from `live/prod/eks/stack`:
```bash
cd .terragrunt-stack/eks/addons/loki/s3/chunks
terragrunt destroy
```

If the error is on the `eks/addons/loki/s3/ruler` unit, do the same with the `prod-loki-ruler` bucket and the unit's directory.

To avoid the error, set `force_destroy = true` before destroying, as in [Destroy the Prod Stack](/docs/iac/remove-eks-forge/#destroy-the-prod-stack).
