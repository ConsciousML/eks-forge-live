locals {
  version = "v0.1.9.2"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_owner_live        = local.github_locals.github_owner_live
  github_repo_name_live    = local.github_locals.github_repo_name_live
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog

  github_token = get_env("GITHUB_TOKEN")

  # GitHub's `sub` prefix for the repository. Holds owner and repo IDs with immutable subject claims.
  subject_claim_prefix = run_cmd("--terragrunt-quiet", "gh", "api", "repos/${local.github_owner_live}/${local.github_repo_name_live}/actions/oidc/customization/sub", "--jq", ".sub_claim_prefix // error(\"sub_claim_prefix missing from GitHub API response\")")
}

stack "aws_gh_actions_auth" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//stacks/aws_gh_actions_auth?ref=${local.version}"
  path   = "github_actions_bootstrap"
  values = {
    version                  = local.version
    github_owner_catalog     = local.github_owner_catalog
    github_repo_name_catalog = local.github_repo_name_catalog
    github_owner             = local.github_owner_live
    github_repo_name         = local.github_repo_name_live
    subject_claim_prefix     = local.subject_claim_prefix
    github_token             = local.github_token
    iam_role_name            = "gh-tg-live-eks-role"
    max_session_duration     = 9000
    policy_arns = [
      "arn:aws:iam::aws:policy/AdministratorAccess",
    ]
    inline_policies = [
      {
        name = "EKSFullAccessLive"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid    = "EKSFullAccessLive"
              Effect = "Allow"
              Action = [
                "eks:CreateCluster",
                "eks:DeleteCluster",
                "eks:DescribeCluster",
                "eks:ListClusters",
                "eks:UpdateClusterConfig",
                "eks:UpdateClusterVersion",
                "eks:DescribeUpdate",
                "eks:TagResource",
                "eks:UntagResource",
                "eks:ListTagsForResource",
                "eks:CreateFargateProfile",
                "eks:DeleteFargateProfile",
                "eks:DescribeFargateProfile",
                "eks:ListFargateProfiles",
                "eks:CreateNodegroup",
                "eks:DeleteNodegroup",
                "eks:DescribeNodegroup",
                "eks:ListNodegroups",
                "eks:UpdateNodegroupConfig",
                "eks:UpdateNodegroupVersion",
                "eks:CreateAddon",
                "eks:DeleteAddon",
                "eks:DescribeAddon",
                "eks:DescribeAddonVersions",
                "eks:ListAddons",
                "eks:UpdateAddon",
                "eks:CreateAccessEntry",
                "eks:DeleteAccessEntry",
                "eks:DescribeAccessEntry",
                "eks:ListAccessEntries",
                "eks:AssociateAccessPolicy",
                "eks:DisassociateAccessPolicy",
                "eks:ListAssociatedAccessPolicies",
                "eks:AssociateIdentityProviderConfig",
                "eks:DisassociateIdentityProviderConfig",
                "eks:DescribeIdentityProviderConfig",
                "eks:ListIdentityProviderConfigs",
                "eks:CreatePodIdentityAssociation",
                "eks:DeletePodIdentityAssociation",
                "eks:DescribePodIdentityAssociation",
                "eks:ListPodIdentityAssociations",
              ]
              Resource = "*"
            }
          ]
        })
      }
    ]
    github_branch        = "*"
    oidc_url             = "https://token.actions.githubusercontent.com"
    oidc_client_id_list  = ["sts.amazonaws.com"]
    oidc_thumbprint_list = []
    create_oidc_provider = false
    deploy_key_repositories = [
      local.github_repo_name_live,
      local.github_repo_name_catalog,
    ]
    deploy_key_secret_names = [
      "DEPLOY_KEY_TG_LIVE",
      "DEPLOY_KEY_TG_CATALOG",
    ]
    deploy_key_title = "Terragrunt Live EKS Deploy Key"
  }
}

unit "aws_caller_identity" {
  source = "git::git@github.com:${local.github_owner_catalog}/${local.github_repo_name_catalog}.git//units/aws_caller_identity/?ref=${local.version}"
  path   = "aws_caller_identity"
  values = { version = local.version }
}

unit "secret_eks_local_admin" {
  source = "git::git@github.com:${local.github_owner_catalog}/${local.github_repo_name_catalog}.git//units/github/secrets/eks_local_admin/?ref=${local.version}"
  path   = "secret_eks_local_admin"
  values = {
    version          = local.version
    github_token     = local.github_token
    github_repo_name = local.github_repo_name_live
  }
}
