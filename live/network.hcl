locals {
  # Must stay in sync with vpc_cidrs in the catalog repo's pipelines/network.hcl:
  # https://github.com/ConsciousML/eks-forge-catalog/blob/main/pipelines/network.hcl
  vpc_cidrs = {
    prod    = "10.0.0.0/16"
    staging = "10.1.0.0/16"
  }

  # Offset within each private subnet CIDR for each interface endpoint's pinned ENI IP.
  # ecr.api and ecr.dkr are provisioned for NAT cost savings only. No CiliumNetworkPolicy
  # consumes them (node image pulls, including registry auth, go through kubelet, not a
  # pod's Cilium endpoint). Neither has an app_param_key_map entry below. sts has no
  # current CNP consumer either (Karpenter's world rule only covers EC2 Fleet + SQS), add
  # it to app_param_key_map if a future consumer needs it.
  endpoint_host_offsets = {
    secretsmanager       = 10
    route53              = 11
    "ecr.api"            = 12
    "ecr.dkr"            = 13
    ec2                  = 14
    sts                  = 15
    elasticloadbalancing = 16
    sqs                  = 17
    iam                  = 18
    tagging              = 19
    shield               = 20
    acm                  = 21
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
    shield               = "shield"
    acm                  = "acm"
  }
}
