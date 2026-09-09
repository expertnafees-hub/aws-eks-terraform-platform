terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 6.0" }
    helm = { source = "hashicorp/helm", version = "~> 3.0" }
  }
  backend "s3" {}
}
variable "aws_region" { type = string }
variable "cluster_name" { type = string }
variable "vpc_id" { type = string }
variable "oidc_provider_arn" { type = string }
variable "oidc_provider_url" { type = string }
variable "hosted_zone_id" { type = string }
variable "chart_versions" { type = map(string) }
provider "aws" { region = var.aws_region }
data "aws_eks_cluster" "this" { name = var.cluster_name }
provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.aws_region]
    }
  }
}
module "addons" {
  source            = "../../../modules/addons"
  cluster_name      = var.cluster_name
  vpc_id            = var.vpc_id
  region            = var.aws_region
  oidc_provider_arn = var.oidc_provider_arn
  oidc_provider_url = var.oidc_provider_url
  hosted_zone_id    = var.hosted_zone_id
  chart_versions    = var.chart_versions
}
