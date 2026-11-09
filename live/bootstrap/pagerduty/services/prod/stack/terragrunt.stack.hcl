locals {
  version = "v0.2.1"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog

  environment = read_terragrunt_config(find_in_parent_folders("environment.hcl")).locals.environment
}

stack "pagerduty_service" {
  source = "git::git@github.com:${local.github_owner_catalog}/${local.github_repo_name_catalog}.git//stacks/pagerduty_service?ref=${local.version}"
  path   = "pagerduty_service"

  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    token                    = get_env("PAGERDUTY_TOKEN")
    service_region           = get_env("PAGERDUTY_SERVICE_REGION", "")
    environment              = local.environment
  }
}
