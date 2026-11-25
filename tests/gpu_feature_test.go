package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
)

// kubectlTimeout bounds each kubectl call so a stuck API server can't hang a check.
const kubectlTimeout = 30 * time.Second

// Suspended CronJob from the app of apps' manifests/features/gpu/smoke-test.
const (
	gpuNamespace        = "gpu"
	gpuSmokeTestCronJob = "gpu-smoke-test"
)

// assertGPUFeature triggers one run of the gpu smoke test CronJob and fails unless its Job
// completes. The Job's activeDeadlineSeconds bounds the run and its TTL deletes it. Skipped unless
// FEATURE_GPU_ENABLED is "true", which CI and CD export from the feature_toggles bootstrap's
// GitHub variables.
func assertGPUFeature(t *testing.T) {
	t.Helper()

	if os.Getenv("FEATURE_GPU_ENABLED") != "true" {
		t.Log("[INFO] gpu feature disabled, skipping its checks")
		return
	}

	name := fmt.Sprintf("%s-terratest-%d", gpuSmokeTestCronJob, time.Now().Unix())
	kubectl(t, "create", "job", "--from=cronjob/"+gpuSmokeTestCronJob, name, "-n", gpuNamespace)
	t.Logf("[INFO] started GPU smoke test job %s", name)

	var job struct {
		Status struct {
			Conditions []struct {
				Type    string `json:"type"`
				Status  string `json:"status"`
				Reason  string `json:"reason"`
				Message string `json:"message"`
			} `json:"conditions"`
		} `json:"status"`
	}
	for {
		require.NoError(t, json.Unmarshal([]byte(kubectl(t, "get", "job", name, "-n", gpuNamespace, "-o", "json")), &job))
		for _, c := range job.Status.Conditions {
			if c.Status != "True" {
				continue
			}
			switch c.Type {
			case "Complete":
				t.Logf("[INFO] GPU smoke test job %s passed", name)
				return
			case "Failed":
				t.Errorf("[ERROR] GPU smoke test job %s failed: %s %s", name, c.Reason, c.Message)
				return
			}
		}
		time.Sleep(10 * time.Second)
	}
}

// kubectl runs kubectl with args and returns its stdout, failing the test on error.
func kubectl(t *testing.T, args ...string) string {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), kubectlTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "kubectl", args...).Output()
	require.NoError(t, err, "[ERROR] kubectl %s failed", strings.Join(args, " "))
	return string(out)
}
