terraform {
  required_providers {
    helm = { source = "hashicorp/helm", version = "~> 3.0" }
  }
}
variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "region" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "hosted_zone_id" { type = string }
variable "chart_versions" { type = map(string) }
locals {
  identities = {
    lb           = "system:serviceaccount:kube-system:aws-load-balancer-controller"
    certificates = "system:serviceaccount:cert-manager:cert-manager"
  }
}
resource "aws_iam_role" "controller" {
  for_each = local.identities
  name     = "${var.cluster_name}-${each.key}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRoleWithWebIdentity"
      Principal = { Federated = var.oidc_provider_arn }
      Condition = { StringEquals = {
        "${replace(var.oidc_provider_url, "https://", "")}:sub" = each.value
        "${replace(var.oidc_provider_url, "https://", "")}:aud" = "sts.amazonaws.com"
      } }
    }]
  })
}
resource "aws_iam_role_policy" "lb" {
  role   = aws_iam_role.controller["lb"].id
  policy = file("${path.module}/load-balancer-policy.json")
}
resource "aws_iam_role_policy" "certificates" {
  role = aws_iam_role.controller["certificates"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["route53:GetChange"], Resource = "arn:aws:route53:::change/*" },
      { Effect = "Allow", Action = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets"], Resource = "arn:aws:route53:::hostedzone/${var.hosted_zone_id}" }
    ]
  })
}
resource "helm_release" "lb" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_versions["load_balancer"]
  atomic     = true
  timeout    = 600
  values = [yamlencode({
    clusterName    = var.cluster_name, region = var.region, vpcId = var.vpc_id
    serviceAccount = { name = "aws-load-balancer-controller", annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.controller["lb"].arn } }
  })]
  depends_on = [aws_iam_role_policy.lb]
}
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_versions["traefik"]
  atomic           = true
  timeout          = 600
  values = [yamlencode({
    deployment = { replicas = 2 }
    service = { annotations = {
      "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
      "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
      "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
    } }
    ingressRoute = { dashboard = { enabled = false } }
  })]
  depends_on = [helm_release.lb]
}
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_versions["cert_manager"]
  atomic           = true
  timeout          = 600
  values = [yamlencode({
    crds            = { enabled = true }
    serviceAccount  = { name = "cert-manager", annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.controller["certificates"].arn } }
    securityContext = { fsGroup = 1001 }
  })]
  depends_on = [aws_iam_role_policy.certificates]
}
