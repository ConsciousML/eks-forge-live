# Base channel names (no environment prefix, no leading '#'), shared by every environment's
# channels/<environment>/stack. Must stay in sync with the suffix (after "{{ .Values.environment }}-")
# of each `kube-prometheus-stack.alertmanager.config.receivers[].slack_configs[].channel` entry in
# https://github.com/ConsciousML/eks-forge-app-of-apps/blob/main/charts/monitoring/kube-prometheus-stack/values.yaml
locals {
  channel_names = [
    "k8s-critical",
    "k8s-warning",
    "prometheus-stack-critical",
    "prometheus-stack-warning",
    "loki-critical",
    "loki-warning",
    "argocd-critical",
    "argocd-warning",
    "uptime-critical",
    "uptime-warning",
    "watchdog",
    "unrouted",
  ]
}
