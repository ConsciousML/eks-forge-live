generate "provider_helm" {
  path      = "provider_helm.tf"
  if_exists = "overwrite"
  contents  = <<EOF
# Anonymous public ECR pulls hit the shared IP rate limit on CI runners. The token exists only in us-east-1.
ephemeral "aws_ecrpublic_authorization_token" "this" {
  region = "us-east-1"
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }

  registries = [
    {
      url      = "oci://public.ecr.aws"
      username = ephemeral.aws_ecrpublic_authorization_token.this.user_name
      password = ephemeral.aws_ecrpublic_authorization_token.this.password
    }
  ]
}
EOF
}
