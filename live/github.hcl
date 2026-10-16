locals {
  github_owner_catalog         = "ConsciousML"
  github_owner_live            = "ConsciousML"
  github_owner_app_of_apps     = "ConsciousML"
  github_repo_name_catalog     = "eks-forge-catalog"
  github_repo_name_live        = "eks-forge-live"
  github_repo_name_app_of_apps = "eks-forge-app-of-apps"

  # true makes ArgoCD read the app of apps over SSH with the app_of_apps_deploy_key bootstrap's read-only key.
  app_of_apps_private = false
  # One key per app of apps fork, shared by every environment. No {environment}- prefix.
  app_of_apps_deploy_key_secret_name = "${local.github_repo_name_app_of_apps}-argocd-deploy-key"
  # Application repoURL and repository Secret url, which must match exactly. SSH port 443 is open
  # in the argocd-repo-server network policy and listed in ArgoCD's default known hosts.
  app_of_apps_repo_url = (local.app_of_apps_private
    ? "ssh://git@ssh.github.com:443/${local.github_owner_app_of_apps}/${local.github_repo_name_app_of_apps}.git"
    : "https://github.com/${local.github_owner_app_of_apps}/${local.github_repo_name_app_of_apps}"
  )
}
