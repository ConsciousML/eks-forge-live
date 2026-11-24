locals {
  version = "v0.3.0"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_live    = local.github_locals.github_repo_name_live
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog

  # Every FEATURE_<NAME>_ENABLED=true of the shell. get_env can't list variables by pattern.
  enabled_toggles = compact(split("\n", run_cmd("--terragrunt-quiet", "sh", "-c", "env | grep -E '^FEATURE_[A-Z0-9_]+_ENABLED=true$' | cut -d= -f1 || true")))
}

stack "feature_toggles" {
  source = "git::git@github.com:${local.github_owner_catalog}/${local.github_repo_name_catalog}.git//stacks/feature_toggles?ref=${local.version}"
  path   = "feature_toggles"

  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    github_token             = get_env("GITHUB_TOKEN")
    github_repo_name         = local.github_repo_name_live
    enabled_toggles          = local.enabled_toggles
  }
}
