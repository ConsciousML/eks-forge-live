# Test Terragrunt Stacks With Terratest

## Prerequisites 
Perform the [quickstart](../README.md#getting-started) up to `Authenticate with AWS` (included).

## What It Tests

`TestStack` deploys the [staging EKS stack](../live/staging/eks/stack/terragrunt.stack.hcl) end-to-end and validates:

- The stack applies via `terragrunt apply --all`
- Kubeconfig points at the deployed cluster
- ArgoCD's app-of-apps is Synced and Healthy before checking any endpoint, failing fast if it
  stalls for too long
- Each tool's Route53 domain is reachable and, where the tool has an admin password in Secrets Manager, login succeeds:
  - ArgoCD (login)
  - Grafana (login)
  - podinfo
  - Prometheus
  - Alertmanager
  - Hubble
  - Goldilocks
- Destroys the stack automatically (even if it fails)

`TestStackExists` runs the same assertions against an already-deployed stack, skipping apply and destroy. Use it to iterate on test logic without re-deploying infrastructure.

## Run Terratest

Setup the go module (the module is already initialized — run these if you are adding new dependencies):
```bash
go get github.com/gruntwork-io/terratest@v1.0.0
go get github.com/aws/aws-sdk-go-v2@v1.41.7
go get github.com/aws/aws-sdk-go-v2/config@v1.32.17
go get github.com/aws/aws-sdk-go-v2/service/secretsmanager@v1.41.7
go mod tidy
```

Follow the [environment variables guide](https://github.com/ConsciousML/terragrunt-template-catalog-eks/blob/main/docs/environment-variables.md), then run:

```bash
source .env
```

Deploy and test the full stack (apply + assert + destroy). A run can take a while end to end (see
the wait budgets in `app_of_apps_wait_test.go` and `staging_stack_test.go`), so pipe through `tee`
to keep a log file for debugging a stall or failure:
```bash
go test -v -run '^TestStack$' ./tests/... -timeout 120m 2>&1 | tee /tmp/test.log
```

Test against an already-deployed stack (no apply or destroy):
```bash
go test -v -run '^TestStackExists$' ./tests/... -timeout 10m
```

## Tailscale Quirks

`TestStack` shells out to the `tailscale` CLI directly (see `tailscale_reconnect_test.go` and the
top of `staging_stack_test.go`), and the ordering is easy to get wrong.

Tailscale must be down during both apply and destroy, not just one of them. Down before apply
avoids racing the in-cluster connector's split-DNS route. Down before destroy is required because
the operator gets torn down partway through and stops serving the tunnel, so destroy has to
resolve the EKS API publicly instead of through the now-dead private route.

Once the app-of-apps deploy finishes, the test reconnects and flushes the DNS cache so newly
created private DNS records resolve correctly in the assertions that follow. On macOS, a plain
`tailscale down` then `up` doesn't reliably re-push DNS config. Toggling `--accept-dns` off then on
while still down forces the client to reapply it once it comes back up.

See `docs/environment-variables.md` in the catalog repo and `ci.yaml` for how CI sequences the
same down and reconnect steps around its own apply and destroy.

`tailscaled` runs as root, so a plain `tailscale up` or `down` from the unprivileged CI runner
user fails with "prefs write access denied". `.github/actions/setup/action.yml` sets the runner
as Tailscale operator right after connecting, so `TestStack` can reconnect without `sudo`. Locally
your user is already the operator (or root), so this is a no-op.

## Write a Test

Copy `tests/staging_stack_test.go` in the `tests` directory. Use the suffix `*_test.go`.

Next, change the stack directory to the path of the stack you want to test:
```go
stackDir := "../live/staging/eks/stack"
```

Finally, write additional test steps. For example, you can perform health checks or make a request to an API to ensure your infrastructure was deployed properly.
