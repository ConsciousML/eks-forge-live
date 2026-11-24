package tests

import (
	"context"
	"encoding/json"
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
)

var (
	gpuNodePools = []string{"gpu-spot-node-pool", "gpu-on-demand-node-pool"}
	// Application name to the DaemonSet name fragment it deploys.
	gpuDaemonSetApps = map[string]string{
		"gpu-nvidia-device-plugin": "nvidia-device-plugin",
		"gpu-dcgm-exporter":        "dcgm-exporter",
	}
)

// assertGPUFeature checks the gpu feature deployed without running a GPU workload: its
// Applications are Synced and Healthy, its NodePools and EC2NodeClass are Ready, and its
// DaemonSets land on every GPU node of both NodePools. Skipped unless FEATURE_GPU_ENABLED is
// "true", which CI and CD export from the feature_toggles bootstrap's GitHub variables.
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

	ctx, cancel := context.WithTimeout(context.Background(), kubectlTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "kubectl", append(args, "-o", "json")...).Output()
	require.NoError(t, err, "[ERROR] kubectl %s failed", strings.Join(args, " "))
	return out
}
