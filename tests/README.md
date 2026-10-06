{/* This doc is aggregated into the EKS Forge documentation site: https://eks-forge.readthedocs.io/latest/. It is not meant to be read directly in this repository. */}

import Tabs from '@theme/Tabs';
import TabItem from '@theme/TabItem';

## Add an Endpoint Check

An endpoint check polls your tool's hostname until it answers. It's one of the guides of [Update the Live Fork](/docs/deployment/release-a-change-to-production/#update-the-live-fork), and assumes you're on your live branch, with your tool's `domain_name_<tool>` unit in both stack files. If your tool has no such unit, follow [Add a Domain Name Unit](/docs/iac/add-a-domain-name-unit/) first.

Add an entry to `endpointChecks` in [`tests/staging_stack_test.go`](staging_stack_test.go), with `name` set to what follows `domain_name_` in the name of your unit's block in the stack files (e.g. `goldilocks` for `unit "domain_name_goldilocks"`). Pick the tab that fits your tool:
- **Reachability**: the tool answers on its hostname.
- **Login**: the tool also accepts its admin password.

<Tabs groupId="check-type">
<TabItem value="reachability" label="Reachability">

Set `path` to the path to poll, and `validate` to `statusOK`, which passes when the tool answers `200`:
```go
var endpointChecks = []endpointCheck{
	...
	{name: "<tool>", path: "/", validate: statusOK},
}
```

To also check the body of the response, write your own `validate`. For example, Prometheus's entry polls its health path:
```go
	{name: "prometheus", path: "/-/healthy", validate: func(status int, body string) bool {
		return status == http.StatusOK && strings.Contains(body, "Healthy")
	}},
```

</TabItem>
<TabItem value="login" label="Login">

The password must come from a unit with a `secret_name` output, which stores it under the `plaintext` key of its secret, as in the **Generated password** tab of [Create the Secret](/docs/applications/pass-a-secret-to-an-app/#create-the-secret). Set `secretUnit` to the name of that unit's block in the stack files, and `login` to a function you write next:
```go
var endpointChecks = []endpointCheck{
	...
	{name: "<tool>", secretUnit: "<tool>_password", secretKey: "secret_name", login: test<Tool>Login},
}
```

In the same file, write `test<Tool>Login`. It receives the tool's hostname and password, waits for the tool to answer, then logs in. For example, Grafana's, without its log lines:
```go
func testGrafanaLogin(t *testing.T, host string, password string) {
	t.Helper()

	pollUntilReady(t, "https://"+host+"/api/health", endpointRetries, endpointSleep, statusOK)

	var loginResponse struct {
		Message string `json:"message"`
	}
	postLoginJSON(t, "https://"+host+"/login", map[string]string{
		"user":     "admin",
		"password": password,
	}, &loginResponse)
	assert.NotEmpty(t, loginResponse.Message, "[ERROR] Grafana login response message is empty")
}
```

`postLoginJSON` fails the test when the tool doesn't answer `200`.

</TabItem>
</Tabs>

Then continue at [Run the Test on Staging](#run-the-test-on-staging).

## Add a Custom Check

A custom check tests anything that isn't a hostname, such as a Kubernetes or an AWS resource. On your live branch, write it as a [Go](https://go.dev/) function in a new `tests/<name>_test.go`. For example, a check that Karpenter's NodePools exist:
```go
// tests/node_pools_test.go
package tests

import (
	"context"
	"os/exec"
	"testing"

	"github.com/stretchr/testify/require"
)

// assertNodePools fails unless both Karpenter NodePools exist.
func assertNodePools(t *testing.T) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), kubectlTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "kubectl", "get", "nodepool", "critical", "elastic").CombinedOutput()
	require.NoError(t, err, "[ERROR] kubectl get nodepool: %s", out)
	t.Log("[INFO] Karpenter NodePools exist")
}
```

Start every failure message with `[ERROR]`. It's what you search the log for when the test fails in CI (see [Troubleshoot Live CI](/docs/ci-cd/per-repository/troubleshoot-live-ci/#terratest)).

Then call your function from `assertStack`, in [`tests/staging_stack_test.go`](staging_stack_test.go), so that both the CI run and your own run on `staging` execute it:
```go
func assertStack(t *testing.T, ctx context.Context, allOutputs map[string]any, region string) {
	t.Helper()

	assertNodePools(t)
	...
}
```

Reuse the helpers of [`tests/helpers_test.go`](helpers_test.go) where they fit:
- `unitOutput`: reads an output of a unit of the stack, from `allOutputs`.
- `fetchAWSSecret`: reads the `plaintext` key of a Secrets Manager secret.
- `retryUntil`: retries a check until it passes or its budget runs out.

## Run the Test on Staging

From the root of your live fork, check that the tests compile before you deploy anything:
```bash
go vet ./tests/...
```

:::warning
CI deploys to the same `staging` environment. Check that no CI run is in progress before you start. This prints nothing when none is:
```bash
gh run list --workflow ci.yaml --status in_progress
```
:::

Pick the tab that fits your check:
- **Deployed staging**: your check does something no existing check does, such as a custom check or a new login flow, and may take several attempts to get right. You deploy `staging` once, then run only the checks against it, as many times as you need.
- **Full run**: your check copies one that already works, such as another reachability entry, and should pass on the first attempt. The test deploys `staging`, runs the checks, and destroys it, as in CI.

<Tabs groupId="test-run">
<TabItem value="deployed" label="Deployed staging">

Deploy `staging` from your branch, by following [Deploy to Staging](/docs/deployment/get-started/deploy-to-staging/) up to [Test the Stack](/docs/deployment/get-started/deploy-to-staging/#test-the-stack).

Connect to Tailscale, and point `kubectl` at your `staging` cluster, replacing `<region-code>` with the region set in [`live/staging/region.hcl`](../live/staging/region.hcl):
```bash
tailscale up
export AWS_REGION=<region-code>
aws eks update-kubeconfig --region $AWS_REGION --name staging-cluster
```

Then, from the root of your live fork, run `TestStackExists`:
```bash
go test -v -run '^TestStackExists$' ./tests/... -timeout 10m
```

`TestStackExists` runs every check against the cluster you deployed, without applying or destroying anything. For a reachability check, you should see your tool's line, then the test pass:
```text
...
[INFO] <tool> is healthy
...
--- PASS: TestStackExists (...)
PASS
```

If your check fails, fix it and run the test again. You only redeploy when the fix is in a stack file.

Once it passes, destroy `staging` as in [Destroy the Infrastructure](/docs/deployment/get-started/deploy-to-staging/#destroy-the-infrastructure), so it doesn't collide with CI.

</TabItem>
<TabItem value="full" label="Full run">

`TestStack` deploys `staging` itself, so don't deploy it first. From the root of your live fork, run it, replacing `<region-code>` with the region set in [`live/staging/region.hcl`](../live/staging/region.hcl):
```bash
source .env
export AWS_REGION=<region-code>
go test -v -run '^TestStack$' ./tests/... -timeout 90m 2>&1 | tee /tmp/test.log
```

It takes around 1 hour. The test disconnects and reconnects Tailscale by itself, so leave Tailscale alone while it runs.

:::warning
Don't interrupt the run. A test stopped halfway never reaches its destroy, and leaves a `staging` cluster and a state lock behind (see [Destroy a Leftover Staging](/docs/ci-cd/per-repository/troubleshoot-live-ci/#destroy-a-leftover-staging)).
:::

When it passes, the log ends with:
```text
--- PASS: TestStack (...)
PASS
```

The test destroys `staging` even when it fails, so `/tmp/test.log` is all that's left of the run. Search it for the last `[ERROR]` line, and find what it shows in the table of [Troubleshoot Live CI](/docs/ci-cd/per-repository/troubleshoot-live-ci/#terratest).

</TabItem>
</Tabs>

Then return to [Open a Pull Request](/docs/deployment/release-a-change-to-production/#open-a-pull-request), and use the `run-terratest` label, so CI runs your check too.

## What the Tests Check

In CI, the `terratest` job runs `TestStack`, which:
1. Applies the `staging` stack.
2. Waits for ArgoCD's `app-of-apps` Application to be `Synced` and `Healthy`, which means every application is. It fails early when no application changes state for 10 minutes.
3. Runs the endpoint checks below.
4. Destroys the stack, even when a step failed.

| Tool | Check |
|------|-------|
| ArgoCD | Answers on `/healthz`, and accepts its admin password |
| Grafana | Answers on `/api/health`, and accepts its admin password |
| podinfo | Answers `200` |
| Prometheus | Answers `Healthy` on `/-/healthy` |
| Alertmanager | Answers on `/api/v2/status` |
| Hubble | Answers `200` |
| Goldilocks | Answers `200` |

`TestStackExists` only runs step 3. For what the tests can't catch, see [Limitations](/docs/ci-cd/limitations-and-improvements/#limitations).
