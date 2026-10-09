locals {
  version_catalog     = "v0.1.9.2"
  version_vpc         = "6.6.0"
  version_cluster     = "21.15.1"
  version_aws_lbc     = "3.2.1"
  version_argocd      = "9.5.0"
  version_argocd_apps = "2.0.5"

  version_karpenter_iam            = "21.24.0"
  version_karpenter_helm           = "1.14.0"
  version_prometheus_operator_crds = "30.0.1"
  version_s3                       = "5.15.1"
  version_cilium                   = "1.20.0"

  # PROD: pinned to a release tag instead of dev's "refs/heads/main", so app-of-apps tracks a
  # fixed catalog version instead of the latest commit on main.
  app_of_apps_target_revision = "v0.1.5"

  github_locals            = read_terragrunt_config(find_in_parent_folders("github.hcl")).locals
  github_owner_catalog     = local.github_locals.github_owner_catalog
  github_repo_name_catalog = local.github_locals.github_repo_name_catalog

  environment       = read_terragrunt_config(find_in_parent_folders("environment.hcl")).locals.environment
  cluster_name_full = read_terragrunt_config(find_in_parent_folders("cluster_name_env.hcl")).locals.cluster_name_full
  vpc_cidrs         = read_terragrunt_config(find_in_parent_folders("network.hcl")).locals.vpc_cidrs
  vpc_cidr          = local.vpc_cidrs[local.environment]

  # /19 each (8,187 usable IPs), sized for prefix delegation.
  private_subnets = [cidrsubnet(local.vpc_cidr, 3, 0), cidrsubnet(local.vpc_cidr, 3, 1), cidrsubnet(local.vpc_cidr, 3, 2)]
  public_subnets  = [cidrsubnet(local.vpc_cidr, 3, 3), cidrsubnet(local.vpc_cidr, 3, 4), cidrsubnet(local.vpc_cidr, 3, 5)]

  # PROD: dev has no equivalent, added so CI-deployed clusters can be destroyed locally.
  # IAM principal that needs local destroy access when CI deployed the cluster.
  # Get your ARN: aws sts get-caller-identity --query Arn --output text
  local_admin_arn = get_env("EKS_LOCAL_ADMIN_ARN", "")

  # Shared by every Karpenter NodePool. Only capacity-type differs per pool.
  karpenter_node_pool_base_requirements = [
    {
      key      = "kubernetes.io/arch"
      operator = "In"
      values   = ["amd64", "arm64"]
    },
    {
      key      = "kubernetes.io/os"
      operator = "In"
      values   = ["linux"]
    },
    # Diversify across instance families and sizes for deeper, cheaper spot pools.
    {
      key      = "karpenter.k8s.aws/instance-category"
      operator = "In"
      values   = ["c", "m", "r", "t"]
    },
    {
      key      = "karpenter.k8s.aws/instance-generation"
      operator = "Gt"
      values   = ["2"]
    },
    # Exclude oversized instances so Karpenter never bin-packs onto an expensive
    # instance. nano, micro, and small are too small to be useful: every node runs the same
    # fixed floor of DaemonSets (aws-node, kube-proxy, ebs-csi-node, eks-pod-identity-agent,
    # alloy, loki-canary, cilium-agent) regardless of size, so provisioning more.
    # The instance-cpu and instance-memory requirements below raise the real
    # floor further: size labels are family-relative (a "medium" can be 1 vCPU in one family,
    # 2 in another).
    {
      key      = "karpenter.k8s.aws/instance-size"
      operator = "NotIn"
      values   = ["nano", "micro", "small", "metal"]
    },
    # >= 2 vCPU
    {
      key      = "karpenter.k8s.aws/instance-cpu"
      operator = "Gt"
      values   = ["1"]
    },
    # >= 4 Gb RAM
    {
      key      = "karpenter.k8s.aws/instance-memory"
      operator = "Gt"
      values   = ["4095"]
    }
  ]

  # Holds pods off a new Karpenter node until cilium-agent is ready there, otherwise they get
  # an IP from vpc-cni but no CiliumEndpoint and are treated as `world` by every policy.
  # cilium-operator (on the MNG) removes it. See https://docs.cilium.io/en/latest/installation/taints/
  karpenter_node_pool_startup_taints = [
    {
      key    = "node.cilium.io/agent-not-ready"
      value  = "true"
      effect = "NoExecute"
    }
  ]

  # Required onto the critical NodePool, no fallback to the MNG.
  critical_node_selector = {
    "karpenter.sh/nodepool" = "critical"
  }
  critical_tolerations = [
    {
      key      = "karpenter.sh/workload-class"
      operator = "Equal"
      value    = "critical"
      effect   = "NoSchedule"
    }
  ]

  # Required onto the MNG
  mng_node_selector = {
    "node-role/mng" = "true"
  }
  mng_tolerations = [
    {
      key      = "node-role/mng"
      operator = "Equal"
      value    = "true"
      effect   = "NoSchedule"
    }
  ]
}

# --- VPC + EKS cluster ---

unit "vpc" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/vpc/vpc?ref=${local.version_catalog}"
  path   = "vpc/vpc"

  values = {
    create_vpc = true
    version    = local.version_vpc

    private_subnets = local.private_subnets
    public_subnets  = local.public_subnets

    # PROD: AWS NAT Gateway instead of dev's fck-nat unit, dev's single self-managed NAT
    # instance lacks the managed HA prod needs.
    enable_nat_gateway     = true
    single_nat_gateway     = true
    one_nat_gateway_per_az = false

    enable_dns_hostnames = true
    enable_dns_support   = true

    # PROD: dev disables VPC flow logs to cut cost, prod enables them.
    enable_flow_log                      = true
    create_flow_log_cloudwatch_log_group = true
    create_flow_log_cloudwatch_iam_role  = true

    flow_log_traffic_type             = "REJECT" # only denied traffic reduces log volume
    flow_log_max_aggregation_interval = 600      # 10-min batching vs 60s, fewer records

    # Cost optimization: cheaper CloudWatch log class + short retention
    flow_log_cloudwatch_log_group_class             = "INFREQUENT_ACCESS"
    flow_log_cloudwatch_log_group_retention_in_days = 7

    public_subnet_tags = {
      # Tag for AWS LBC to know where to deploy external ALB
      "kubernetes.io/role/elb" = 1
    }

    private_subnet_tags = {
      # Tag for AWS LBC to know where to deploy external ALB
      "kubernetes.io/role/internal-elb" = 1
      # Tag for Karpenter to discover the private subnet
      "karpenter.sh/discovery" = local.cluster_name_full
    }
  }
}

unit "vpc_endpoint_cidrs" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/vpc/endpoint_cidrs?ref=${local.version_catalog}"
  path   = "vpc/endpoint_cidrs"

  values = {
    version = local.version_catalog
  }
}

unit "vpc_endpoints" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/vpc/endpoints?ref=${local.version_catalog}"
  path   = "vpc/endpoints"

  values = {
    version = local.version_vpc
  }
}

unit "cluster" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/cluster?ref=${local.version_catalog}"
  path   = "eks/cluster"

  values = {
    version = local.version_cluster

    kubernetes_version = "1.36"

    endpoint_public_access  = true
    endpoint_private_access = true

    # Adds the current caller identity as an administrator via cluster access entry
    enable_cluster_creator_admin_permissions = true

    control_plane_scaling_config = {
      tier = "standard"
    }

    # PROD: dev disables control plane logging entirely to cut costs, prod enables "api", see
    # https://github.com/ConsciousML/eks-forge-live/issues/40
    enabled_log_types = ["api"]
    # Infrequent Access cuts cost ~50% but doesn't support all Standard class features:
    # https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CloudWatch_Logs_Log_Classes.html
    cloudwatch_log_group_class             = "INFREQUENT_ACCESS"
    cloudwatch_log_group_retention_in_days = 7

    # Run the following command to see all the available addons:
    # aws eks describe-addon-versions --query 'addons[*].addonName' --output text | tr '\t' '\n'
    # Here's the argument reference for the addons:
    # https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon
    # Read the following for additional information about the available addons:
    # https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html
    addons = {
      # aws-ebs-csi-driver is installed from units/eks/addons/ebs_csi_driver/addon
      coredns = {
        addon_version = "v1.14.2-eksbuild.4"
        configuration_values = jsonencode({
          resources = {
            requests = { cpu = "50m", memory = "48M" }
            limits   = { cpu = "50m", memory = "48M" }
          }
          tolerations = local.mng_tolerations
        })
      }
      eks-pod-identity-agent = {
        before_compute = true
        addon_version  = "v1.3.10-eksbuild.3"
        configuration_values = jsonencode({
          resources = {
            requests = { cpu = "50m", memory = "24M" }
            limits   = { cpu = "50m", memory = "24M" }
          }
        })
      }
      kube-proxy = {
        addon_version = "v1.36.0-eksbuild.7"
        configuration_values = jsonencode({
          # No CPU limit: kube-proxy programs node-level service routing, throttling it
          # breaks Service traffic for every pod on the node.
          resources = {
            requests = { cpu = "11m", memory = "37M" }
            limits   = { memory = "37M" }
          }
          # No tolerations key: this addon's configuration schema doesn't support one, and its
          # default manifest already tolerates everything.
        })
      }
      metrics-server = {
        addon_version = "v0.9.0-eksbuild.2"
        configuration_values = jsonencode({
          resources = {
            requests = { cpu = "11m", memory = "64M" }
            limits   = { cpu = "55m", memory = "64M" }
          }
          tolerations = local.mng_tolerations
        })
      }
      vpc-cni = {
        before_compute = true
        addon_version  = "v1.23.0-eksbuild.1"
        configuration_values = jsonencode({
          env = {
            # Prefix delegation: nodes need more IPs than one-per-ENI allows
            ENABLE_PREFIX_DELEGATION = "true"
          }
          # Policy enforcement moved to Cilium (chaining mode), see the cilium unit below.
          enableNetworkPolicy = "false"
          # aws-node container. No CPU limit: it programs the node's CNI config, throttling it
          # breaks pod sandbox create/delete for every pod scheduled on the node.
          resources = {
            requests = { cpu = "11m", memory = "64M" }
            limits   = { memory = "64M" }
          }
        })
      }
    }

    # Sizing here counts against the account's EC2 Service Quotas, see the catalog repo's
    # pipelines/bootstrap/aws_service_quotas.
    eks_managed_node_groups = {
      "${local.environment}_ng" = {
        # Starting on 1.30, AL2023 is the default AMI type for EKS managed node groups
        ami_type = "AL2023_x86_64_STANDARD"

        # Pin to a specific AMI release to prevent unintended rolling node replacements on every apply.
        # use_latest_ami_release_version defaults to true upstream, which silently ignores this pin.
        # Find available versions with:
        # aws ssm get-parameters-by-path --path /aws/service/eks/optimized-ami/1.36/amazon-linux-2023/x86_64/standard --query 'Parameters[].Name'
        use_latest_ami_release_version = false
        ami_release_version            = "1.36.2-20260709"

        instance_types = ["t3.medium"]

        capacity_type = "ON_DEMAND"

        min_size     = 2
        desired_size = 2
        max_size     = 10

        # Blocks pods from reaching instance metadata: pods sit at hop 2, only the node itself (hop 1) can get a token
        metadata_options = {
          http_tokens                 = "required"
          http_put_response_hop_limit = 1
          http_endpoint               = "enabled"
        }

        # Reserves the MNG for pods that tolerate it (Karpenter's controller, cilium-operator,
        # Hubble Relay and UI, the cilium_cep_restart Job).
        # The taint alone doesn't attract those pods, mng_node_selector also needs this label.
        labels = local.mng_node_selector

        taints = {
          mng = {
            key    = "node-role/mng"
            value  = "true"
            effect = "NO_SCHEDULE"
          }
        }
      }
    }

    # Disable EKS Auto mode
    compute_config = {
      enabled = false
    }

    # PROD: dev always sets access_entries = {}, prod conditionally grants a local admin entry.
    # Only needed when CI deployed the cluster and you need to run destroy locally.
    # Get your ARN with: aws sts get-caller-identity --query Arn --output text
    access_entries = local.local_admin_arn != "" ? {
      local_admin = {
        principal_arn = local.local_admin_arn
        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    } : {}
  }
}

# --- EBS CSI driver ---

unit "ebs_csi_driver_iam_role" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/ebs_csi_driver/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/ebs_csi_driver/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

unit "ebs_csi_driver_addon" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/ebs_csi_driver/addon?ref=${local.version_catalog}"
  path   = "eks/addons/ebs_csi_driver/addon"

  values = {
    version       = local.version_catalog
    addon_version = "v1.62.0-eksbuild.1"
    tags          = {}
    configuration_values = jsonencode({
      # Single resources block per pod, applied to every sidecar container in it
      controller = {
        resources = {
          requests = { cpu = "11m", memory = "24M" }
          limits   = { memory = "24M" }
        }
        tolerations = local.mng_tolerations
      }
      node = {
        resources = {
          requests = { cpu = "50m", memory = "24M" }
          limits   = { cpu = "50m", memory = "24M" }
        }
        tolerations = local.mng_tolerations
      }
    })
  }
}

# --- Route53 + ACM ---

unit "route53_hosted_zone_public" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/route53/hosted_zone_public?ref=${local.version_catalog}"
  path   = "eks/route53/hosted_zone_public"

  values = {
    version = local.version_catalog
    comment = "Managed by Terraform"
    create  = false
  }
}

unit "route53_hosted_zone_private" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/route53/hosted_zone_private?ref=${local.version_catalog}"
  path   = "eks/route53/hosted_zone_private"

  values = {
    version = local.version_catalog
    comment = "Managed by Terraform"
  }
}

unit "acm_certificate" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/route53/acm_certificate?ref=${local.version_catalog}"
  path   = "eks/route53/acm_certificate"

  values = {
    version = local.version_catalog
  }
}

# --- External Secrets Operator ---
# Only the IAM/Pod Identity resources are Terraform-managed; the Helm release lives in
# app-of-apps.

unit "iam_role_eso" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/external_secrets_operator/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/external_secrets_operator/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

# --- Loki ---
# Only the S3/Pod Identity resources are Terraform-managed. The Helm release lives in
# app-of-apps.

unit "loki_s3_chunks" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/loki/s3/chunks?ref=${local.version_catalog}"
  path   = "eks/addons/loki/s3/chunks"

  values = {
    version = local.version_s3
    tags    = {}
    # PROD: dev sets force_destroy = true so the dev stack can be torn down without emptying
    # the bucket first, prod keeps it false to prevent accidental data loss.
    force_destroy = false
  }
}

unit "loki_s3_ruler" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/loki/s3/ruler?ref=${local.version_catalog}"
  path   = "eks/addons/loki/s3/ruler"

  values = {
    version = local.version_s3
    tags    = {}
    # PROD: dev sets force_destroy = true so the dev stack can be torn down without emptying
    # the bucket first, prod keeps it false to prevent accidental data loss.
    force_destroy = false
  }
}

unit "iam_role_loki" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/loki/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/loki/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

# --- Prometheus Operator CRDs ---
# Installed ahead of ArgoCD so the ServiceMonitor CRD already exists by the time anything
# renders one.

unit "prometheus_operator_crds" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/prometheus_stack/crds?ref=${local.version_catalog}"
  path   = "eks/addons/prometheus_stack/crds"

  values = {
    version            = local.version_catalog
    helm_chart_version = local.version_prometheus_operator_crds
  }
}

# --- ArgoCD ---

unit "argocd" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/argocd/helm?ref=${local.version_catalog}"
  path   = "eks/addons/argocd/helm"

  values = {
    version            = local.version_catalog
    helm_chart_version = local.version_argocd
    helm_values = {
      configs = {
        params = {
          "server.insecure" = true
          # Caps concurrent GenerateManifest calls so a resync burst can't starve the
          # repo-server's own healthz handler behind a backlog of manifest renders.
          "reposerver.parallelism.limit" = 20
          # Matches ARGOCD_EXEC_TIMEOUT below: the controller's own deadline for the
          # GenerateManifest RPC is a separate 60s default that isn't covered by it.
          "controller.repo.server.timeout.seconds" = "180"
        }
        cm = {
          # Restores the Application CRD health check ArgoCD removed by default in v1.8+.
          # Without this, sync-wave ordering between nested Applications (app-of-apps) is a
          # no-op: a child Application with no health assessment reports healthy immediately
          # on creation, so a later wave proceeds without waiting for it to actually converge.
          "resource.customizations.health.argoproj.io_Application" = <<-LUA
            hs = {}
            hs.status = "Progressing"
            hs.message = ""
            if obj.status ~= nil then
              if obj.status.health ~= nil then
                hs.status = obj.status.health.status
                if obj.status.health.message ~= nil then
                  hs.message = obj.status.health.message
                end
              end
            end
            return hs
          LUA
        }
      }
      # Scraped for the argo-cd-mixin dashboards (https://github.com/adinhodovic/argo-cd-mixin).
      controller = {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
        resources = {
          requests = { cpu = "1388m", memory = "1645M" }
          limits   = { memory = "1645M" }
        }
        # Outranks the DaemonSets' daemonset-critical (eks-forge-app-of-apps's
        # priority-classes/), so it can no longer be preempted to make room for one of them
        # on a full node.
        priorityClassName = "system-node-critical"
        nodeSelector      = local.critical_node_selector
        tolerations       = local.critical_tolerations
      }
      repoServer = {
        replicas = 2
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
        resources = {
          requests = { cpu = "100m", memory = "717M" }
          limits   = { memory = "717M" }
        }
        # healthz?full=true does real dependency checks that can exceed 1s on cold start.
        readinessProbe = { timeoutSeconds = 10 }
        livenessProbe  = { timeoutSeconds = 10 }
        env = [
          { name = "ARGOCD_EXEC_TIMEOUT", value = "180s" }
        ]
        # Spreads the 2 replicas across AZs so a single node's CPU contention (or loss)
        # can't stall manifest generation for every Application at once.
        topologySpreadConstraints = [
          {
            maxSkew           = 1
            topologyKey       = "topology.kubernetes.io/zone"
            whenUnsatisfiable = "DoNotSchedule"
          }
        ]
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      notifications = {
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = true
          }
        }
        resources = {
          requests = { cpu = "50m", memory = "64M" }
          limits   = { cpu = "50m", memory = "64M" }
        }
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      applicationSet = {
        resources = {
          requests = { cpu = "50m", memory = "64M" }
          limits   = { cpu = "50m", memory = "64M" }
        }
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      server = {
        resources = {
          requests = { cpu = "11m", memory = "150M" }
          limits   = { cpu = "55m", memory = "150M" }
        }
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      redis = {
        resources = {
          requests = { cpu = "11m", memory = "35M" }
          limits   = { cpu = "55m", memory = "35M" }
        }
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      # Separate Job from `redis` itself (initializes its auth secret), doesn't inherit
      # redis's nodeSelector/tolerations, needs its own.
      redisSecretInit = {
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
      dex = {
        resources = {
          requests = { cpu = "11m", memory = "64M" }
          limits   = { cpu = "55m", memory = "64M" }
        }
        nodeSelector = local.critical_node_selector
        tolerations  = local.critical_tolerations
      }
    }
  }
}

unit "argocd_password" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/argocd/aws_secret_password?ref=${local.version_catalog}"
  path   = "eks/addons/argocd/aws_secret_password"

  values = {
    version                 = local.version_catalog
    length                  = 16
    recovery_window_in_days = 0
    tags                    = {}
  }
}

unit "argocd_app_of_apps" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/argocd/app_of_apps?ref=${local.version_catalog}"
  path   = "eks/addons/argocd/app_of_apps"

  values = {
    version   = local.version_catalog
    name      = "app-of-apps"
    namespace = "argocd"
    path      = "apps"
    # Fully qualified release tag: resolves directly instead of scanning all branches/tags.
    target_revision       = local.app_of_apps_target_revision
    project               = "default"
    destination_namespace = "argocd"
    destination_server    = "https://kubernetes.default.svc"
    finalizers            = ["resources-finalizer.argocd.argoproj.io"]
    sync_options          = ["CreateNamespace=true"]
    prune                 = true
    helm_chart_version    = local.version_argocd_apps
    retry = {
      limit = 7
      backoff = {
        duration     = "5s"
        factor       = 2
        max_duration = "2m"
      }
    }
  }
}

# --- AWS Load Balancer Controller ---
# Only the AWS-side IAM/Pod Identity resources are Terraform-managed; the Helm release
# lives in app-of-apps.

unit "iam_policy_aws_lbc" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/aws_load_balancer_controller/iam_policy_url?ref=${local.version_catalog}"
  path   = "eks/addons/aws_load_balancer_controller/iam_policy_url"

  values = {
    version = local.version_catalog
    url     = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${local.version_aws_lbc}/docs/install/iam_policy.json"
  }
}

unit "iam_role_aws_lbc" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/aws_load_balancer_controller/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/aws_load_balancer_controller/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

# --- ExternalDNS ---
# Only the AWS-side IAM/Pod Identity resources are Terraform-managed; the Helm releases
# live in app-of-apps.

unit "iam_role_external_dns_private" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/external_dns/private/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/external_dns/private/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

unit "iam_role_external_dns_public" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/external_dns/public/iam_role?ref=${local.version_catalog}"
  path   = "eks/addons/external_dns/public/iam_role"

  values = {
    version = local.version_catalog
    tags    = {}
  }
}

# --- Tailscale ---
# Only the Tailscale-API Terraform resources (OAuth client, split DNS) are managed here;
# the operator Helm release and Connector CRD live in app-of-apps. The ACL policy lives in
# the pipelines/bootstrap/tailscale stack, not the EKS stack.

unit "tailscale_oauth_client_tailscale_operator" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/tailscale/oauth_client_tailscale_operator?ref=${local.version_catalog}"
  path   = "eks/addons/tailscale/oauth_client_tailscale_operator"

  values = {
    version = local.version_catalog
  }
}

unit "tailscale_oauth_client_secret" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/tailscale/oauth_client_secret?ref=${local.version_catalog}"
  path   = "eks/addons/tailscale/oauth_client_secret"

  values = {
    version                 = local.version_catalog
    recovery_window_in_days = 0
    tags                    = {}
  }
}

unit "tailscale_split_dns_default" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/tailscale/split_dns/default?ref=${local.version_catalog}"
  path   = "eks/addons/tailscale/split_dns/default"

  values = {
    version = local.version_catalog
  }
}

unit "tailscale_split_dns_eks_endpoint" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/tailscale/split_dns/eks?ref=${local.version_catalog}"
  path   = "eks/addons/tailscale/split_dns/eks"

  values = {
    version = local.version_catalog
  }
}

# --- Cilium ---
# Installed on the MNG before Karpenter: Karpenter nodes carry Cilium's agent-not-ready startup
# taint, and cilium-operator (which removes it) can't depend on a Karpenter node.

unit "cilium" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/cilium/helm?ref=${local.version_catalog}"
  path   = "eks/addons/cilium/helm"

  values = {
    version            = local.version_catalog
    helm_chart_version = local.version_cilium
    helm_values = {
      # Chaining mode: layers onto vpc-cni instead of replacing it, for Hubble flow visibility and NetworkPolicy enforcement.
      cni = {
        chainingMode = "aws-cni"
        exclusive    = false
        # Chained mode: vpc-cni immediately takes over once the conflist is gone, so
        # removing it on agent shutdown/uninstall doesn't leave nodes unmanaged.
        uninstall = true
      }
      routingMode          = "native"
      enableIPv4Masquerade = false
      kubeProxyReplacement = false
      # Cilium is the sole NetworkPolicy enforcer. vpc-cni's own enforcement stays
      # disabled (EKS default), so the two don't conflict.
      policyEnforcementMode = "default"
      # L7 proxy, unneeded for L3/4 flow visibility, would add another DaemonSet per node.
      envoy = {
        enabled = false
      }

      # Background worker: no CPU limit, throttling the dataplane risks packet drops cluster-wide.
      resources = {
        requests = { cpu = "63m", memory = "273M" }
        limits   = { memory = "273M" }
      }

      # Relay and UI on the MNG: Hubble stays up to troubleshoot Karpenter node networking
      # even when no Karpenter node is healthy.
      hubble = {
        enabled = true
        relay = {
          enabled  = true
          replicas = 1
          # Web API: bursty with flow-query load, needs CPU headroom.
          resources = {
            requests = { cpu = "23m", memory = "50M" }
            limits   = { cpu = "100m", memory = "50M" }
          }
          prometheus = {
            serviceMonitor = { enabled = true }
          }
          nodeSelector = local.mng_node_selector
          tolerations  = local.mng_tolerations
        }
        ui = {
          enabled  = true
          replicas = 1
          backend = {
            # Web API: bursty with dashboard usage.
            resources = {
              requests = { cpu = "49m", memory = "127M" }
              limits   = { cpu = "200m", memory = "127M" }
            }
            securityContext = { readOnlyRootFilesystem = true }
          }
          frontend = {
            # Lightweight idle: static assets, no burst shape to plan for.
            resources = {
              requests = { cpu = "11m", memory = "20Mi" }
              limits   = { cpu = "11m", memory = "20Mi" }
            }
            # Safe with a read-only root: the chart already mounts an emptyDir at /tmp
            # for nginx's cache/pid paths.
            securityContext = { readOnlyRootFilesystem = true }
          }
          nodeSelector = local.mng_node_selector
          tolerations  = local.mng_tolerations
        }
        metrics = {
          # Dynamic exporter: metric changes hot reload without a cilium-agent restart. dns and
          # http are excluded, both need the L7 proxy (envoy disabled above), and L7 visibility
          # is a known limitation of aws-cni chaining mode.
          enabled = []
          dynamic = {
            enabled = true
            config = {
              configMapName   = "cilium-dynamic-metrics-config"
              createConfigMap = true
              content = [
                for name in ["drop", "tcp", "flow", "icmp", "policy", "port-distribution"] : {
                  name = name
                  contextOptions = concat(
                    [
                      { name = "sourceContext", values = ["workload-name", "dns", "reserved-identity"] },
                      { name = "destinationContext", values = ["workload-name", "dns", "reserved-identity"] },
                    ],
                    name == "port-distribution" ? [] : [
                      {
                        name = "labelsContext"
                        values = name == "policy" ? ["source_namespace", "destination_namespace"] : [
                          "source_namespace", "destination_namespace", "traffic_direction"
                        ]
                      }
                    ]
                  )
                }
              ]
            }
          }
          serviceMonitor = { enabled = true }
          dashboards = {
            enabled     = true
            annotations = { grafana_folder = "Hubble" }
          }
        }
      }

      # Requires the ServiceMonitor CRD from prometheus_operator_crds.
      prometheus = {
        enabled        = true
        serviceMonitor = { enabled = true }
      }
      dashboards = {
        enabled     = true
        annotations = { grafana_folder = "Cilium" }
      }

      # On the MNG: removes the agent-not-ready startup taint from Karpenter nodes, so it can't
      # run on one itself.
      operator = {
        replicas = 2
        # Chained CNI still needs a local cilium-agent to build the pod sandbox, and
        # agents wait on the operator for CRDs: hostNetwork: false can deadlock a
        # restart. true avoids the chained path, like cilium-agent itself.
        hostNetwork     = true
        securityContext = { readOnlyRootFilesystem = true }
        # gops (started for pprof/debugging) writes its socket file under $HOME on boot;
        # with a read-only root that write fails and the operator never starts.
        extraVolumes      = [{ name = "gops", emptyDir = {} }]
        extraVolumeMounts = [{ name = "gops", mountPath = "/home/gops" }]
        prometheus = {
          serviceMonitor = { enabled = true }
        }
        dashboards = {
          enabled     = true
          annotations = { grafana_folder = "Cilium" }
        }
        nodeSelector = local.mng_node_selector
        tolerations  = local.mng_tolerations
      }
    }
  }
}

# Restarts workloads whose pods started before cilium-agent (coredns, metrics-server, created
# with the cluster), they'd have no CiliumEndpoint. Helm post hook: the apply blocks on it, so
# Karpenter only installs once it's done.
unit "cilium_cep_restart" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/cilium/cep_restart?ref=${local.version_catalog}"
  path   = "eks/addons/cilium/cep_restart"

  values = {
    version        = local.version_catalog
    cilium_version = local.version_cilium
    node_selector  = local.mng_node_selector
    tolerations    = local.mng_tolerations
  }
}

# --- Karpenter ---

unit "karpenter_iam" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/karpenter/iam?ref=${local.version_catalog}"
  path   = "eks/addons/karpenter/iam"

  values = {
    version = local.version_karpenter_iam
    # Set to true when using `SPOT` instances
    enable_spot_termination = true
    tags                    = {}
  }
}

unit "karpenter_helm" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/karpenter/helm?ref=${local.version_catalog}"
  path   = "eks/addons/karpenter/helm"

  values = {
    version            = local.version_catalog
    helm_chart_version = local.version_karpenter_helm
    helm_values = {
      settings = {
        enableZonalShift = false
      }
      controller = {
        resources = {
          requests = { cpu = "163m", memory = "512M" }
          limits   = { memory = "512M" }
        }
      }
      # Requires the ServiceMonitor CRD from prometheus_operator_crds.
      serviceMonitor = {
        enabled = true
      }
      nodeSelector = local.mng_node_selector
      tolerations  = local.mng_tolerations
    }
  }
}

unit "karpenter_ec2_node_class" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/karpenter/ec2_node_class?ref=${local.version_catalog}"
  path   = "eks/addons/karpenter/ec2_node_class"

  values = {
    version = local.version_catalog
    name    = "default"
    # PROD: dev uses ami_alias = "al2023@latest", prod pins a tested AMI release instead so
    # nodes don't roll on every new AMI publish.
    ami_alias = "al2023@v20260618"
    # Matches kubelet's own default (what the MNG's nodes already get). Without this, Karpenter
    # computes a lower ceiling from the plain per-ENI formula, blind to the VPC CNI addon's
    # ENABLE_PREFIX_DELEGATION setting, which starves small instance types of pod slots.
    kubelet_max_pods = 110
    # Karpenter's own uninstall waits for it to deprovision all nodes owned by this class first;
    # the helm_release module's 300s default is too short under load.
    timeout = 600
  }
}

# Sizing here counts against the account's EC2 Service Quotas, see the catalog repo's
# pipelines/bootstrap/aws_service_quotas.
unit "karpenter_node_pool_critical" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/karpenter/node_pool/critical?ref=${local.version_catalog}"
  path   = "eks/addons/karpenter/node_pool/critical"

  values = {
    version = local.version_catalog
    name    = "critical"
    requirements = concat(
      [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          # PROD: dev uses "spot" for the critical NodePool, prod uses on-demand so critical
          # workloads aren't subject to spot interruption.
          values = ["on-demand"]
        }
      ],
      local.karpenter_node_pool_base_requirements
    )
    taints = [
      {
        key    = "karpenter.sh/workload-class"
        value  = "critical"
        effect = "NoSchedule"
      }
    ]
    startup_taints = local.karpenter_node_pool_startup_taints
    disruption = {
      consolidationPolicy = "Balanced"
      consolidateAfter    = "15m"
      budgets = [
        {
          nodes = "1"
        }
      ]
    }
    limits_cpu = "32"
    # Long enough for Loki/Prometheus/ArgoCD to shut down cleanly, short enough to bound how
    # long a blocking PDB can delay a drift-driven AMI/CVE patch.
    termination_grace_period = "30m"
    expire_after             = "720h"
  }
}

# Sizing here counts against the account's EC2 Service Quotas, see the catalog repo's
# pipelines/bootstrap/aws_service_quotas.
unit "karpenter_node_pool_elastic" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/karpenter/node_pool/elastic?ref=${local.version_catalog}"
  path   = "eks/addons/karpenter/node_pool/elastic"

  values = {
    version = local.version_catalog
    name    = "elastic"
    requirements = concat(
      [
        {
          key      = "karpenter.sh/capacity-type"
          operator = "In"
          values   = ["spot"]
        },
      ],
      local.karpenter_node_pool_base_requirements
    )
    taints = [
      {
        key    = "karpenter.sh/workload-class"
        value  = "elastic"
        effect = "NoSchedule"
      }
    ]
    startup_taints = local.karpenter_node_pool_startup_taints
    disruption = {
      consolidationPolicy = "WhenEmptyOrUnderutilized"
      consolidateAfter    = "2m"
      budgets = [
        {
          nodes = "50%"
        }
      ]
    }
    limits_cpu = "16"
    # Bounds worst-case drain time for elastic workloads, which tolerate disruption well.
    termination_grace_period = "2m"
    expire_after             = "720h"
  }
}

unit "grafana_password" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/prometheus_stack/grafana/aws_secret_password?ref=${local.version_catalog}"
  path   = "eks/addons/prometheus_stack/grafana/aws_secret_password"

  values = {
    version                 = local.version_catalog
    length                  = 16
    recovery_window_in_days = 0
    tags                    = {}
  }
}

unit "alertmanager_slack_bot_secret" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/addons/prometheus_stack/alertmanager/aws_secret_slack_bot?ref=${local.version_catalog}"
  path   = "eks/addons/prometheus_stack/alertmanager/aws_secret_slack_bot"

  values = {
    version                 = local.version_catalog
    bot_token               = get_env("SLACK_BOT_TOKEN")
    recovery_window_in_days = 0
    tags                    = {}
  }
}

# --- Domain names ---

unit "domain_name_argocd" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/argocd?ref=${local.version_catalog}"
  path   = "eks/domain_name/argocd"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_podinfo" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/podinfo?ref=${local.version_catalog}"
  path   = "eks/domain_name/podinfo"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_prometheus" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/prometheus?ref=${local.version_catalog}"
  path   = "eks/domain_name/prometheus"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_alertmanager" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/alertmanager?ref=${local.version_catalog}"
  path   = "eks/domain_name/alertmanager"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_grafana" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/grafana?ref=${local.version_catalog}"
  path   = "eks/domain_name/grafana"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_goldilocks" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/goldilocks?ref=${local.version_catalog}"
  path   = "eks/domain_name/goldilocks"

  values = {
    version = local.version_catalog
  }
}

unit "domain_name_hubble" {
  source = "github.com/${local.github_owner_catalog}/${local.github_repo_name_catalog}//units/eks/domain_name/hubble?ref=${local.version_catalog}"
  path   = "eks/domain_name/hubble"

  values = {
    version = local.version_catalog
  }
}
