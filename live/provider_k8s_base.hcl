locals {
  cluster_hcl       = find_in_parent_folders("cluster_name_env.hcl")
  cluster_name_full = read_terragrunt_config(local.cluster_hcl).locals.cluster_name_full

  cluster_exists = run_cmd("--terragrunt-quiet", "sh", "-c", <<-EOT
    output=$(aws eks describe-cluster --name ${local.cluster_name_full} 2>&1)
    aws_exit_code=$?
    if echo "$output" | grep -q 'ResourceNotFoundException'; then
      echo false
    elif [ $aws_exit_code -ne 0 ]; then
      echo "$output" >&2
      exit 1
    else
      echo true
    fi
  EOT
  )
}

inputs = {
  cluster_name = local.cluster_name_full
}

exclude {
  if      = !local.cluster_exists
  actions = ["init", "validate", "plan", "destroy"]
}

generate "provider_k8s_base" {
  path      = "provider_k8s_base.tf"
  if_exists = "overwrite"
  contents  = <<EOF
data "aws_eks_cluster" "this" {
  name = var.cluster_name
}
EOF
}
