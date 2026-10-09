package tests

import (
	"cmp"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terragrunt"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestStack deploys the staging EKS stack and validates every tool in endpointChecks.
func TestStack(t *testing.T) {
	t.Parallel()

	ctx := t.Context()

	region := requireRegion(t)

	// Tailscale CLI is needed to flush DNS cache after Terragrunt apply
	_, err := exec.LookPath("tailscale")
	require.NoError(t, err, "[ERROR] tailscale CLI not found in PATH — install it before running this test")

	// Disconnect before apply to avoid racing the in-cluster connector's split-DNS route (see
	// ci.yaml). Reconnected once the stack and connector are up (reconnectTailscale below).
	out, err := exec.Command("tailscale", "down").CombinedOutput()
	require.NoError(t, err, "[ERROR] tailscale down: %s", strings.TrimSpace(string(out)))

	stackDir := "../live/staging/eks/stack"

	options := &terragrunt.Options{
		TerragruntDir:  stackDir,
		TerragruntArgs: []string{"--log-level", "error"},
	}

	defer terragrunt.DestroyAllContext(t, ctx, options)

	// Runs before destroy (LIFO). Avoids "Required plugins are not installed"
	// (gruntwork-io/terragrunt#1960) by forcing a fresh stack generate before destroy.
	defer terragrunt.StackCleanContext(t, ctx, options)

	// Runs before both defers above (LIFO) no matter what fails afterward. During destroy
	// the tailscale operator is torn down partway through and stops serving the tunnel, so
	// destroy must resolve the EKS API publicly rather than through the now-dead private route.
	defer func() {
		out, err := exec.Command("tailscale", "down").CombinedOutput()
		assert.NoError(t, err, "[ERROR] tailscale down before destroy: %s", strings.TrimSpace(string(out)))
	}()

	terragrunt.ApplyAllContext(t, ctx, options)

	waitAndAssertStack(t, ctx, stackDir, region)
}

// TestProdStack validates every tool in endpointChecks on the prod EKS stack CD just applied.
// Never applies or destroys.
func TestProdStack(t *testing.T) {
	t.Parallel()

	region := requireRegion(t)

	waitAndAssertStack(t, t.Context(), "../live/prod/eks/stack", region)
}

// TestStackExists runs only the assertion phase against an already-deployed
// stack. Use this when the infrastructure is already up and you want to
// iterate on the Go logic without triggering an apply or destroy.
//
// Usage:
//
//	go test -v -run TestStackExists -timeout 10m
//	TERRATEST_TARGET_ENVIRONMENT=prod go test -v -run TestStackExists -timeout 10m
func TestStackExists(t *testing.T) {
	if os.Getenv("GITHUB_ACTIONS") == "true" {
		t.Skip("skipped in CI — run locally against an already-deployed stack")
	}

	t.Parallel()

	ctx := t.Context()

	// Checks staging unless TERRATEST_TARGET_ENVIRONMENT names another environment, such as prod.
	environment := cmp.Or(os.Getenv("TERRATEST_TARGET_ENVIRONMENT"), "staging")
	stackDir := "../live/" + environment + "/eks/stack"

	region := requireRegion(t)

	assertStack(t, ctx, stackOutputs(t, ctx, stackDir), region)
}
