terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
  required_version = ">= 1.3"
}

provider "aws" {
  region = local.region
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Detect if WSParticipantRole exists (only present in Workshop Studio accounts)
data "aws_iam_roles" "wsparticipant" {
  name_regex = "^WSParticipantRole$"
}

locals {
  name            = "eks-auto"
  region          = "--AWS_REGION--"
  cluster_version = "--EKS_VERSION--"
  account_id      = "--AWS_ACCOUNT_ID--"

  vpc_cidr = "10.254.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  # True only when WSParticipantRole exists (Workshop Studio environment)
  wsparticipant_role_exists = length(data.aws_iam_roles.wsparticipant.names) > 0

  tags = {
    Blueprint  = local.name
    Workshop   = "amazon-eks-security-immersion-day"
  }
}

###############################################################
# EKS Cluster - Auto Mode
#
# NOTE: We do not set cluster_encryption_config here. If you want
# KMS encryption for Kubernetes secrets, the terraform-aws-modules/eks
# module's `kms` submodule can create a key automatically when encryption
# is configured. We omitted it to keep the template idempotent on reruns
# (the module-created alias/eks/<cluster-name> can otherwise conflict
# with leftovers from a failed previous apply).
###############################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.34"

  cluster_name    = local.name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access = true

  # Authentication mode: the module defaults to "API" only, but this workshop's
  # IAM Groups/Roles module demonstrates the aws-auth ConfigMap and the
  # API_AND_CONFIG_MAP -> API migration, which require the ConfigMap to exist.
  # Start in API_AND_CONFIG_MAP so those labs work; the switching-modes lab then
  # shows the one-way migration to API.
  authentication_mode = "API_AND_CONFIG_MAP"

  # Control plane logging.
  # Pre-enable a subset so historical logs exist for the Detective Controls
  # "Analyze Control Plane / CloudWatch Logs Insights" lab (the queries need
  # pre-existing data). The lab then has participants enable "authenticator"
  # themselves as the visible before/after step.
  # On EKS Auto Mode all five control plane log types (api, audit, authenticator,
  # controllerManager, scheduler) are user-configurable.
  cluster_enabled_log_types = ["api", "audit", "scheduler"]

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable EKS Auto Mode
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system", "general-purpose"]
  }

  # NOTE: This cluster runs pure EKS Auto Mode — no vpc-cni/kube-proxy add-ons
  # and no classic managed node groups are defined here. The kube-bench module
  # (Regulatory Compliance) provisions a temporary AL2023 node group and the
  # add-ons it needs on demand (see static/terraform/kube-bench), and removes
  # them in its cleanup step, so they never affect the rest of the workshop.

  access_entries = {
    # Grant WSParticipantRole cluster admin access (only when the role exists,
    # i.e., in Workshop Studio-provisioned accounts; ignored in standalone test accounts)
    for k, v in {
      participant = {
        principal_arn     = "arn:aws:iam::${local.account_id}:role/WSParticipantRole"
        type              = "STANDARD"
        kubernetes_groups = []

        policy_associations = {
          admin = {
            policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = {
              type = "cluster"
            }
          }
        }
      }
    } : k => v if local.wsparticipant_role_exists
  }

  tags = local.tags
}


###############################################################
# IAM Role for custom NodeClass (Auto Mode)
###############################################################

resource "aws_iam_role" "custom_nodeclass_role" {
  name = "${local.name}-${local.region}-AmazonEKSAutoNodeRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodeMinimalPolicy"
  role       = aws_iam_role.custom_nodeclass_role.name
}

resource "aws_iam_role_policy_attachment" "ecr_pull_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
  role       = aws_iam_role.custom_nodeclass_role.name
}

# Register custom node role with EKS Auto Mode
resource "aws_eks_access_entry" "custom_nodeclass_access" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.custom_nodeclass_role.arn
  type          = "EC2"
}

resource "aws_eks_access_policy_association" "custom_nodeclass_policy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.custom_nodeclass_role.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAutoNodePolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.custom_nodeclass_access]
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

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

################################################################################
# Outputs
################################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "region" {
  description = "AWS region"
  value       = local.region
}
