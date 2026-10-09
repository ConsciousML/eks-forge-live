package tests

import (
	"context"
	"testing"
)

// waitAndAssertStack waits for the applied stack in stackDir to settle, then runs every check.
func waitAndAssertStack(t *testing.T, ctx context.Context, stackDir string, region string) {
	t.Helper()

	// Fetched once and reused below: terragrunt output --all is expensive to re-run.
	allOutputs := stackOutputs(t, ctx, stackDir)

	updateKubeconfig(t, allOutputs, region)

	waitForAppOfApps(t)

	reconnectTailscale(t)

	assertStack(t, ctx, allOutputs, region)
}

// assertStack runs every check against allOutputs.
func assertStack(t *testing.T, ctx context.Context, allOutputs map[string]any, region string) {
	t.Helper()

	assertEndpoints(t, ctx, allOutputs, region)
}
