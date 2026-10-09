locals {
  version = "v0.1.9.2"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog

  environment   = read_terragrunt_config(find_in_parent_folders("environment.hcl")).locals.environment
  channel_names = read_terragrunt_config(find_in_parent_folders("channels.hcl")).locals.channel_names
}

stack "slack_channels" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//stacks/slack_channels?ref=${local.version}"
  path   = "slack_channels"

  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    bot_token                = get_env("SLACK_BOT_TOKEN")
    environment              = local.environment
    channel_names            = local.channel_names
  }
}
