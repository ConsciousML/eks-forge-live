package tests

import (
	"context"
	"encoding/json"
	"fmt"
	"maps"
	"os"
	"os/exec"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// kubectlTimeout bounds each kubectl call so a stuck API server can't hang a check.
const kubectlTimeout = 30 * time.Second

// Names from the catalog's stacks/gpu (name = "gpu") and the app of apps' apps/features/gpu.
const (
	gpuAppOfAppsName = "app-of-apps-gpu"
	gpuNamespace     = "gpu"
	gpuEC2NodeClass  = "gpu-ec2-node-class"
	gpuTaintKey      = "karpenter.sh/workload-class"
	gpuTaintValue    = "gpu"
	gpuNodeLabel     = "karpenter.k8s.aws/instance-gpu-manufacturer"

	// Suspended CronJob from the app of apps' manifests/features/gpu/smoke-test.
	gpuSmokeTestCronJob = "gpu-smoke-test"
	gpuSmokeTestPassed  = "Test PASSED"
	// The Job's activeDeadlineSeconds (15m) plus pod startup and log slack.
	gpuSmokeTestTimeout = 17 * time.Minute
	gpuSmokeTestPoll    = 10 * time.Second
)

var (
	gpuNodePools = []string{"gpu-spot-node-pool", "gpu-on-demand-node-pool"}
	// Application name to the DaemonSet name fragment it deploys.
	gpuDaemonSetApps = map[string]string{
		"gpu-nvidia-device-plugin": "nvidia-device-plugin",
		"gpu-dcgm-exporter":        "dcgm-exporter",
	}
)

// assertGPUFeature checks the gpu feature: its Applications are Synced and Healthy, its NodePools
// and EC2NodeClass are Ready, its DaemonSets tolerate the gpu taint and select NVIDIA nodes, and
// the GPU smoke test passes. Skipped unless
// FEATURE_GPU_ENABLED is "true", which CI and CD export from the feature_toggles bootstrap's
// GitHub variables.
func assertGPUFeature(t *testing.T) {
	t.Helper()

	if os.Getenv("FEATURE_GPU_ENABLED") != "true" {
		t.Log("[INFO] gpu feature disabled, skipping its checks")
		return
	}

	apps, err := listApps(t)
	require.NoError(t, err, "[ERROR] kubectl get application failed")
	for _, name := range append([]string{gpuAppOfAppsName}, slices.Collect(maps.Keys(gpuDaemonSetApps))...) {
		app, found := apps.find(name)
		if assert.True(t, found, "[ERROR] application %s not found", name) {
			assert.Equal(t, "Synced", app.Status.Sync.Status, "[ERROR] application %s sync", name)
			assert.Equal(t, "Healthy", app.Status.Health.Status, "[ERROR] application %s health", name)
		}
	}

	assertReady(t, "ec2nodeclass", gpuEC2NodeClass)
	for _, name := range gpuNodePools {
		assertReady(t, "nodepool", name)
	}

	var daemonSets struct {
		Items []struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
			Spec struct {
				Template struct {
					Spec struct {
						NodeSelector map[string]string `json:"nodeSelector"`
						Affinity     json.RawMessage   `json:"affinity"`
						Tolerations  []struct {
							Key    string `json:"key"`
							Value  string `json:"value"`
							Effect string `json:"effect"`
						} `json:"tolerations"`
					} `json:"spec"`
				} `json:"template"`
			} `json:"spec"`
		} `json:"items"`
	}
	require.NoError(t, json.Unmarshal(kubectlJSON(t, "get", "daemonset", "-n", gpuNamespace), &daemonSets))

	for _, fragment := range gpuDaemonSetApps {
		found := false
		for _, ds := range daemonSets.Items {
			if !strings.Contains(ds.Metadata.Name, fragment) {
				continue
			}
			found = true
			pod := ds.Spec.Template.Spec

			// Both NodePools carry the gpu taint and launch NVIDIA instances only.
			tolerates := false
			for _, tol := range pod.Tolerations {
				if tol.Key == gpuTaintKey && tol.Value == gpuTaintValue && tol.Effect == "NoSchedule" {
					tolerates = true
				}
			}
			assert.True(t, tolerates, "[ERROR] daemonset %s doesn't tolerate %s=%s:NoSchedule", ds.Metadata.Name, gpuTaintKey, gpuTaintValue)

			_, selects := pod.NodeSelector[gpuNodeLabel]
			selects = selects || strings.Contains(string(pod.Affinity), gpuNodeLabel)
			assert.True(t, selects, "[ERROR] daemonset %s doesn't select %s", ds.Metadata.Name, gpuNodeLabel)
		}
		assert.True(t, found, "[ERROR] no daemonset matching %s in namespace %s", fragment, gpuNamespace)
	}

	assertGPUSmokeTest(t)
}

// assertGPUSmokeTest triggers one run of the gpu-smoke-test CronJob and fails unless its Job
// completes and logs "Test PASSED" within gpuSmokeTestTimeout. The Job's TTL deletes it.
func assertGPUSmokeTest(t *testing.T) {
	t.Helper()

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
	for deadline := time.Now().Add(gpuSmokeTestTimeout); ; {
		require.NoError(t, json.Unmarshal(kubectlJSON(t, "get", "job", name, "-n", gpuNamespace), &job))
		for _, c := range job.Status.Conditions {
			if c.Status != "True" {
				continue
			}
			switch c.Type {
			case "Complete":
				logs := kubectl(t, "logs", "job/"+name, "-n", gpuNamespace)
				assert.Contains(t, logs, gpuSmokeTestPassed, "[ERROR] GPU smoke test job %s logs", name)
				t.Logf("[INFO] GPU smoke test job %s passed", name)
				return
			case "Failed":
				t.Errorf("[ERROR] GPU smoke test job %s failed: %s %s", name, c.Reason, c.Message)
				return
			}
		}
		if time.Now().After(deadline) {
			t.Errorf("[ERROR] GPU smoke test job %s didn't finish within %s", name, gpuSmokeTestTimeout)
			return
		}
		time.Sleep(gpuSmokeTestPoll)
	}
}

// assertReady checks the cluster-scoped kind/name has a Ready condition set to True.
func assertReady(t *testing.T, kind string, name string) {
	t.Helper()

	var obj struct {
		Status struct {
			Conditions []struct {
				Type   string `json:"type"`
				Status string `json:"status"`
			} `json:"conditions"`
		} `json:"status"`
	}
	require.NoError(t, json.Unmarshal(kubectlJSON(t, "get", kind, name), &obj))

	for _, c := range obj.Status.Conditions {
		if c.Type == "Ready" {
			assert.Equal(t, "True", c.Status, "[ERROR] %s %s not Ready", kind, name)
			return
		}
	}
	t.Errorf("[ERROR] %s %s has no Ready condition", kind, name)
}

// kubectlJSON runs kubectl with args and -o json, failing the test on error.
func kubectlJSON(t *testing.T, args ...string) []byte {
	t.Helper()

	return []byte(kubectl(t, append(args, "-o", "json")...))
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
