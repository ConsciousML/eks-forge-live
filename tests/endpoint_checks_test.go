package tests

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"

	http_helper "github.com/gruntwork-io/terratest/modules/http-helper"
	"github.com/stretchr/testify/assert"
)

// endpointRetries and endpointSleep bound how long each endpoint check waits for its tool
// to become reachable. waitForAppOfApps already confirms every app is healthy, so this
// budget only covers DNS propagation and ALB/target-group lag, not app startup.
const (
	endpointRetries = 30
	endpointSleep   = 10 * time.Second
)

// endpointCheck describes one stack tool to verify after deploy. An entry with no secretUnit
// is checked for plain reachability via validate. One with a secretUnit fetches the password
// from Secrets Manager and hands it to login instead. Add a new tool here to cover it.
type endpointCheck struct {
	name       string                                           // domain_name_<name> stack output
	path       string                                           // path to poll, only used when secretUnit is empty
	validate   func(status int, body string) bool               // reachability check, only used when secretUnit is empty
	secretUnit string                                           // stack unit exposing the password secret name, empty means no auth
	secretKey  string                                           // output key on secretUnit holding the secret name
	login      func(t *testing.T, host string, password string) // auth check, only used when secretUnit is set
}

// statusOK is a validate func for endpoints where reaching the page at all is proof enough.
func statusOK(status int, _ string) bool {
	return status == http.StatusOK
}

var endpointChecks = []endpointCheck{
	{name: "argocd", secretUnit: "argocd_password", secretKey: "secret_name", login: testArgoCDLogin},
	{name: "podinfo", path: "/", validate: statusOK},
	{name: "grafana", secretUnit: "grafana_password", secretKey: "secret_name", login: testGrafanaLogin},
	{name: "prometheus", path: "/-/healthy", validate: func(status int, body string) bool {
		return status == http.StatusOK && strings.Contains(body, "Healthy")
	}},
	{name: "alertmanager", path: "/api/v2/status", validate: func(status int, body string) bool {
		return status == http.StatusOK && strings.Contains(body, "cluster")
	}},
	{name: "hubble", path: "/", validate: statusOK},
	{name: "goldilocks", path: "/", validate: statusOK},
}

// assertEndpoints runs every check in endpointChecks against allOutputs.
func assertEndpoints(t *testing.T, ctx context.Context, allOutputs map[string]any, region string) {
	t.Helper()

	for _, ep := range endpointChecks {
		host := unitOutput(t, allOutputs, "domain_name_"+ep.name, "value")

		if ep.secretUnit == "" {
			url := "https://" + host + ep.path
			t.Logf("[INFO] polling %s until %s is ready", url, ep.name)
			pollUntilReady(t, url, endpointRetries, endpointSleep, ep.validate)
			t.Logf("[INFO] %s is healthy", ep.name)
			continue
		}

		secretName := unitOutput(t, allOutputs, ep.secretUnit, ep.secretKey)
		password := fetchAWSSecret(t, ctx, region, secretName)
		ep.login(t, host, password)
	}
}

// pollUntilReady polls url until validate passes, sleeping sleepBetweenRetries between attempts
// up to retries times.
func pollUntilReady(t *testing.T, url string, retries int, sleepBetweenRetries time.Duration, validate func(int, string) bool) {
	t.Helper()

	retryUntil(t, retries, sleepBetweenRetries, func() {
		t.Fatalf("[ERROR] %s did not become ready after %d retries", url, retries)
	}, func(attempt int) (ready bool, abort bool) {
		status, body, err := http_helper.HttpGetE(t, url, nil)
		if err == nil && validate(status, body) {
			return true, false
		}

		if err != nil {
			t.Logf("[ERROR] poll %s attempt %d/%d failed: %v", url, attempt, retries+1, err)
		} else {
			t.Logf("[ERROR] poll %s attempt %d/%d failed: unexpected status %d", url, attempt, retries+1, status)
		}
		return false, false
	})
}

// testArgoCDLogin asserts that ArgoCD is healthy and that a login request with
// the given credentials returns a valid session token.
func testArgoCDLogin(t *testing.T, host string, password string) {
	t.Helper()

	t.Logf("[INFO] polling https://%s/healthz until ArgoCD is ready", host)
	pollUntilReady(t, "https://"+host+"/healthz", endpointRetries, endpointSleep, statusOK)
	t.Log("[INFO] ArgoCD is healthy")

	t.Logf("[INFO] logging in to ArgoCD at https://%s/api/v1/session", host)
	var session struct {
		Token string `json:"token"`
	}
	postLoginJSON(t, "https://"+host+"/api/v1/session", map[string]string{
		"username": "admin",
		"password": password,
	}, &session)
	assert.NotEmpty(t, session.Token, "[ERROR] ArgoCD session token is empty — login may have succeeded but returned no token")
	t.Log("[INFO] ArgoCD login succeeded and session token received")
}

// testGrafanaLogin asserts that Grafana is healthy and that an admin login request with
// the given credentials succeeds.
func testGrafanaLogin(t *testing.T, host string, password string) {
	t.Helper()

	t.Logf("[INFO] polling https://%s/api/health until Grafana is ready", host)
	pollUntilReady(t, "https://"+host+"/api/health", endpointRetries, endpointSleep, statusOK)
	t.Log("[INFO] Grafana is healthy")

	t.Logf("[INFO] logging in to Grafana at https://%s/login", host)
	var loginResponse struct {
		Message string `json:"message"`
	}
	postLoginJSON(t, "https://"+host+"/login", map[string]string{
		"user":     "admin",
		"password": password,
	}, &loginResponse)
	assert.NotEmpty(t, loginResponse.Message, "[ERROR] Grafana login response message is empty — login may have failed")
	t.Log("[INFO] Grafana login succeeded")
}
