variable "name" { type = string }
variable "kubernetes_version" { type = string }
variable "subnet_ids" { type = list(string) }
variable "api_security_group_id" { type = string }
variable "cluster_role_arn" { type = string }
variable "node_role_arn" { type = string }
variable "operator_role_arn" { type = string }
variable "instance_types" { type = list(string) }
variable "addon_versions" { type = map(string) }
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name}/cluster"
  retention_in_days = 14
}
resource "aws_eks_cluster" "this" {
  name                      = var.name
  role_arn                  = var.cluster_role_arn
  version                   = var.kubernetes_version
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = false
    security_group_ids      = [var.api_security_group_id]
  }
  depends_on = [aws_cloudwatch_log_group.cluster]
}
resource "aws_eks_access_entry" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = var.operator_role_arn
  type          = "STANDARD"
}
resource "aws_eks_access_policy_association" "operator" {
  cluster_name  = aws_eks_cluster.this.name
  principal_arn = aws_eks_access_entry.operator.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]
}
resource "aws_iam_role" "cni" {
  name = "${var.name}-vpc-cni"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = aws_iam_openid_connect_provider.this.arn }
      Condition = { StringEquals = {
        "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-node"
        "${replace(aws_iam_openid_connect_provider.this.url, "https://", "")}:aud" = "sts.amazonaws.com"
      } }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "cni" {
  role       = aws_iam_role.cni.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_eks_addon" "cni" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "vpc-cni"
  addon_version            = var.addon_versions["vpc-cni"]
  service_account_role_arn = aws_iam_role.cni.arn
  depends_on               = [aws_iam_role_policy_attachment.cni]
}
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name}-general"
  node_role_arn   = var.node_role_arn
  subnet_ids      = var.subnet_ids
  instance_types  = var.instance_types
  ami_type        = "AL2023_x86_64_STANDARD"
  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }
  update_config { max_unavailable = 1 }
  depends_on = [aws_eks_addon.cni]
}
resource "aws_eks_addon" "core" {
  for_each      = { for k, v in var.addon_versions : k => v if k != "vpc-cni" }
  cluster_name  = aws_eks_cluster.this.name
  addon_name    = each.key
  addon_version = each.value
  depends_on    = [aws_eks_node_group.this]
}
output "cluster_name" { value = aws_eks_cluster.this.name }
output "oidc_provider_arn" { value = aws_iam_openid_connect_provider.this.arn }
output "oidc_provider_url" { value = aws_iam_openid_connect_provider.this.url }
