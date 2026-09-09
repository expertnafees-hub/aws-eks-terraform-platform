terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
  backend "s3" {}
}
provider "aws" {
  region = var.aws_region
  default_tags { tags = { Project = "eks-portfolio", Environment = var.environment, ManagedBy = "Terraform" } }
}
variable "aws_region" { type = string }
variable "environment" { type = string }
variable "vpc_cidr" { type = string }
variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Use at least two distinct Availability Zones."
  }
}
variable "single_nat" { type = bool }
variable "api_client_cidrs" {
  type = set(string)
  validation {
    condition     = length(var.api_client_cidrs) > 0 && !contains(var.api_client_cidrs, "0.0.0.0/0")
    error_message = "Specify connected operator CIDRs; do not use 0.0.0.0/0."
  }
}
variable "operator_role_arn" { type = string }
variable "kubernetes_version" { type = string }
variable "addon_versions" { type = map(string) }
variable "instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}
locals { name = "nafees-${var.environment}" }
module "vpc" {
  source     = "../../../modules/vpc"
  name       = local.name
  cidr       = var.vpc_cidr
  azs        = var.availability_zones
  single_nat = var.single_nat
}
module "iam" {
  source = "../../../modules/iam"
  name   = local.name
}
module "security" {
  source           = "../../../modules/security"
  name             = local.name
  vpc_id           = module.vpc.vpc_id
  api_client_cidrs = var.api_client_cidrs
}
module "eks" {
  source                = "../../../modules/eks"
  name                  = local.name
  kubernetes_version    = var.kubernetes_version
  subnet_ids            = module.vpc.private_subnet_ids
  api_security_group_id = module.security.api_security_group_id
  cluster_role_arn      = module.iam.cluster_role_arn
  node_role_arn         = module.iam.node_role_arn
  operator_role_arn     = var.operator_role_arn
  instance_types        = var.instance_types
  addon_versions        = var.addon_versions
  depends_on            = [module.iam, module.vpc]
}
output "cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "oidc_provider_url" { value = module.eks.oidc_provider_url }
