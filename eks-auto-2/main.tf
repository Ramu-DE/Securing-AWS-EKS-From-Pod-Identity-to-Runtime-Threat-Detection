##############################################################################
# Second EKS Auto Mode cluster for the VPC Lattice labs (Terraform)
#
# Replaces the eksctl-based creation of `eks-auto-2` (eksctl is itself a
# CloudFormation wrapper). Provisions, with no CloudFormation anywhere:
#   * A dedicated VPC (10.254.0.0/16) with public + private subnets and a
#     single NAT gateway.
#   * An EKS **Auto Mode** cluster named `eks-auto-2` (v1.36) with a public
#     API endpoint, matching the primary `eks-auto` cluster.
#
# VPC Lattice connects the two clusters at the application layer, so the two
# VPCs do NOT need to be peered and their CIDRs may overlap.
#
# Run:
#   terraform init
#   terraform apply -auto-approve
##############################################################################

terraform {
  required_version = ">= 1.3"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
  }
}

# Region comes from the environment (AWS_REGION / AWS_DEFAULT_REGION / ambient config).
provider "aws" {}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}

locals {
  name            = "eks-auto-2"
  cluster_version = "1.36"
  vpc_cidr        = "10.254.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  region          = data.aws_region.current.name

  tags = {
    Blueprint = "EKSSecurityImmersionDayLattice"
    Workshop  = "amazon-eks-security-immersion-day"
  }
}

################################################################################
# VPC
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# EKS Auto Mode cluster
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.34"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable EKS Auto Mode (managed compute; Pod Identity built in).
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system", "general-purpose"]
  }

  tags = local.tags
}

################################################################################
# Outputs
################################################################################

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "Second cluster name"
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Second cluster API server endpoint"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Second cluster VPC ID"
}

output "vpc_cidr" {
  value       = local.vpc_cidr
  description = "Second cluster VPC CIDR"
}

output "private_subnet_ids" {
  value       = module.vpc.private_subnets
  description = "Second cluster private subnet IDs"
}

output "region" {
  value       = local.region
  description = "AWS region"
}
