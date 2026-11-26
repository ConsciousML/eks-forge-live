locals {
  # Must stay in sync with vpc_cidrs in the catalog repo's pipelines/network.hcl:
  # https://github.com/ConsciousML/eks-forge-catalog/blob/main/pipelines/network.hcl
  vpc_cidrs = {
    prod    = "10.0.0.0/16"
    staging = "10.1.0.0/16"
  }

  # Offset within each private subnet CIDR for each interface endpoint's pinned ENI IP.
  # Every entry needs a critical-pod consumer in app_param_key_map below. Unused offsets are spare.
  # A pod is critical if its IAM role can read secrets, change DNS, launch compute, pass IAM roles, or change network exposure.
  endpoint_host_offsets = {
    secretsmanager       = 10
    route53              = 11
    ec2                  = 14
    elasticloadbalancing = 16
    sqs                  = 17
    iam                  = 18
    tagging              = 19
    acm                  = 21
    ssm                  = 22
    eks                  = 23
  }

  # Consumer-side keys matching the vpcEndpointCidrs shape each CiliumNetworkPolicy
  # consumer expects in eks-forge-app-of-apps.
  app_param_key_map = {
    secretsmanager       = "secretsmanager"
    route53              = "route53"
    ec2                  = "ec2"
    elasticloadbalancing = "elasticloadbalancing"
    sqs                  = "sqs"
    iam                  = "iam"
    tagging              = "tagging"
    acm                  = "acm"
    ssm                  = "ssm"
    eks                  = "eks"
  }
}
