locals {
  version = "v0.1.9.2"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_live    = local.github_locals.github_repo_name_live
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog
}

stack "slack" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//stacks/slack?ref=${local.version}"
  path   = "slack"

  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    github_token             = get_env("GITHUB_TOKEN")
    github_repo_name         = local.github_repo_name_live
    bot_token                = get_env("SLACK_BOT_TOKEN")
  }
}
