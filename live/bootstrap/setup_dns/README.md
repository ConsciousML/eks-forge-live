{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}
### Setup DNS
This pipeline creates a public hosted zone for `staging` and for `prod`.

In [`live/dns.hcl`](../../dns.hcl), set `base_domain` to the domain you used in the catalog:
```hcl
locals {
  base_domain = "yourdomain.com"
  ...
}
```

:::info
Each subdirectory provisions its own hosted zone, giving that environment its own subdomain (e.g. `staging.yourdomain.com`):
```
setup_dns/
├── staging/
└── prod/
```
:::

Next, run the following for each environment (replacing `<environment>` with `staging` and then `prod`), from the root of your live fork:
```bash
cd live/bootstrap/setup_dns/<environment>/stack
terragrunt stack clean
terragrunt stack generate
terragrunt run --all apply --backend-bootstrap --non-interactive --no-stack-generate
terragrunt stack output --json setup_dns.route53_hosted_zone.name_servers
```

You should see something similar to:
```txt
{
  "setup_dns": {
    "route53_hosted_zone": {
      "name_servers": [
        "<nameserver_1>",
        "<nameserver_2>",
        "<nameserver_3>",
        "<nameserver_4>"
      ]
    }
  }
}
```

For each environment, add 4 NS records for the environment subdomain in your domain registrar, using the nameservers from the output:

| Type | Host | Value |
|------|------|-------|
| NS | `<environment>` | `ns-123.awsdns-12.com` |
| NS | `<environment>` | `ns-456.awsdns-34.net` |
| NS | `<environment>` | `ns-789.awsdns-56.org` |
| NS | `<environment>` | `ns-012.awsdns-78.co.uk` |

Verify that the NS records are propagated for each environment:
```bash
dig NS <environment>.yourdomain.com
```

Delegation is working when 4 AWS nameservers appear in the `ANSWER SECTION`.

For more information, read [DNS Bootstrap](/docs/quickstart/bootstrap/setup_dns/).
