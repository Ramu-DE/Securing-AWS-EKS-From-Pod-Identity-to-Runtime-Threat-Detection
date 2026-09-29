##############################################################################
# Fully-private EKS Auto Mode cluster (Terraform)
#
# Replaces BOTH the old CloudFormation VPC (`eks-private-vpc.yaml`) AND the
# eksctl cluster creation (eksctl is itself a CloudFormation wrapper).
#
# Provisions, with no CloudFormation anywhere:
#   * An isolated VPC (10.50.0.0/16) whose subnets have NO internet egress
#     (no IGW, no NAT) — the essence of a "fully private" cluster.
#   * Interface VPC endpoints for every AWS service the cluster/nodes need
#     (ECR, STS, EC2, ELB, CloudWatch Logs, Autoscaling, SSM, and crucially
#     eks + eks-auth so EKS Pod Identity works on Auto Mode), plus an S3
#     gateway endpoint for image layers.
#   * An EKS **Auto Mode** cluster with a PRIVATE-ONLY API endpoint.
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
  name            = "eks-auto-private"
  cluster_version = "1.36"
  vpc_cidr        = "10.50.0.0/16"
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  region          = data.aws_region.current.name

  # Interface endpoints the private Auto Mode cluster needs.
  # eks-auth is REQUIRED for EKS Pod Identity credential injection on private nodes.
  interface_endpoints = [
    "ecr.api",
    "ecr.dkr",
    "sts",
    "ec2",
    "elasticloadbalancing",
    "logs",
    "autoscaling",
    "eks",
    "eks-auth",
    "ssm",
    "ssmmessages",
    "ec2messages",
  ]

  tags = {
    Blueprint = "EKSSecurityImmersionDayPrivate"
    Workshop  = "amazon-eks-security-immersion-day"
  }
}

################################################################################
# VPC — isolated subnets (no NAT, no IGW). All AWS access via VPC endpoints.
################################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.19"

  name = local.name
  cidr = local.vpc_cidr

  azs = local.azs

  # Isolated cluster subnets: 10.50.128.0/19, 10.50.160.0/19, 10.50.192.0/19
  intra_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 3, k + 4)]

  enable_nat_gateway   = false
  enable_dns_hostnames = true
  enable_dns_support   = true

  intra_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# VPC Endpoints — the only path from the private cluster to AWS services
################################################################################

# Security group that allows HTTPS from within the VPC to the interface endpoints.
resource "aws_security_group" "vpce" {
  name        = "${local.name}-vpce"
  description = "Allow HTTPS from the VPC to interface VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from within the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name}-vpce" })
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(local.interface_endpoints)

  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${local.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.intra_subnets
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = merge(local.tags, { Name = "${local.name}-${each.value}" })
}

# S3 gateway endpoint (ECR image layers live in S3).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${local.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.vpc.intra_route_table_ids

  tags = merge(local.tags, { Name = "${local.name}-s3" })
}

################################################################################
# EKS Auto Mode cluster — PRIVATE endpoint only
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.34"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  # Fully private: private API endpoint reachable only from inside the VPC
  # (or a peered VPC, e.g. the workshop IDE VPC).
  cluster_endpoint_public_access  = false
  cluster_endpoint_private_access = true

  # Match the primary cluster's auth mode for consistency.
  authentication_mode = "API_AND_CONFIG_MAP"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.intra_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable EKS Auto Mode (managed compute; Pod Identity built in).
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system", "general-purpose"]
  }

  # Endpoints must exist before the cluster tries to reach AWS APIs privately.
  depends_on = [
    aws_vpc_endpoint.interface,
    aws_vpc_endpoint.s3,
  ]

  tags = local.tags
}

################################################################################
# Outputs — consumed by the create-cluster page (peering, tests)
################################################################################

output "cluster_name" {
  value       = module.eks.cluster_name
  description = "Private cluster name"
}

output "cluster_endpoint" {
  value       = module.eks.cluster_endpoint
  description = "Private API server endpoint"
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "Private cluster VPC ID"
}

output "vpc_cidr" {
  value       = local.vpc_cidr
  description = "Private cluster VPC CIDR"
}

output "private_subnet_ids" {
  value       = module.vpc.intra_subnets
  description = "Isolated cluster subnet IDs"
}

output "cluster_security_group_id" {
  value       = module.eks.cluster_security_group_id
  description = "Cluster security group ID"
}

output "region" {
  value       = local.region
  description = "AWS region"
}
