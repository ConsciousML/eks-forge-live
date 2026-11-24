package tests

import (
	"context"
	"encoding/json"
	"os/exec"
	"testing"
)

type argoAppStatus struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Status struct {
		Sync struct {
			Status string `json:"status"`
		} `json:"sync"`
		Health struct {
			Status string `json:"status"`
		} `json:"health"`
	} `json:"status"`
}

type argoAppList struct {
	Items []argoAppStatus `json:"items"`
}

// listApps fetches every Application in the argocd namespace.
func listApps(t *testing.T) (argoAppList, error) {
	t.Helper()

	ctx, cancel := context.WithTimeout(context.Background(), kubectlTimeout)
	defer cancel()

	out, err := exec.CommandContext(ctx, "kubectl", "get", "application", "-n", "argocd", "-o", "json").Output()
	if err != nil {
		return argoAppList{}, err
	}

	var list argoAppList
	if err := json.Unmarshal(out, &list); err != nil {
		return argoAppList{}, err
	}
	return list, nil
}

// find returns the app with the given name, if present.
func (l argoAppList) find(name string) (argoAppStatus, bool) {
	for _, app := range l.Items {
		if app.Metadata.Name == name {
			return app, true
		}
	}
	return argoAppStatus{}, false
}
