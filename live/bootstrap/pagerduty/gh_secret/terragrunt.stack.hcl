locals {
  version = "v0.2.1"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_live    = local.github_locals.github_repo_name_live
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog
}

stack "pagerduty_github_secrets" {
  source = "git::git@github.com:${local.github_owner_catalog}/${local.github_repo_name_catalog}.git//stacks/pagerduty_github_secrets?ref=${local.version}"
  path   = "pagerduty_github_secrets"

  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    github_token             = get_env("GITHUB_TOKEN")
    github_repo_name         = local.github_repo_name_live
    service_region           = get_env("PAGERDUTY_SERVICE_REGION", "")
  }
}
