###############################################################################
# kube-bench node-level assessment infrastructure
#
# The main eks-auto cluster runs pure EKS Auto Mode (Bottlerocket nodes you
# cannot log in to). To run kube-bench directly on an Amazon Linux worker node
# (Lab 0 / Lab 1), this config adds a small, temporary AL2023 managed node group
# to the existing cluster, plus the vpc-cni and kube-proxy add-ons that a classic
# node needs to reach Ready.
#
# This is intentionally SEPARATE from the cluster bootstrap so it exists only
# for the duration of the kube-bench labs. Lab 0 runs `terraform apply` here;
# Lab 5 runs `terraform destroy`. Keeping it out of the main cluster avoids the
# vpc-cni ConfigMap and classic-node scheduling from affecting other modules
# (e.g. Network Policies, which rely on Auto Mode's managed CoreDNS).
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34, < 6.0"
    }
  }
  required_version = ">= 1.3"
}

# Region is taken from the environment (AWS_REGION / AWS_DEFAULT_REGION), which
# the workshop IDE sets for you.
provider "aws" {}

variable "cluster_name" {
  description = "Name of the existing EKS Auto Mode cluster"
  type        = string
  default     = "eks-auto"
}

variable "node_group_name" {
  description = "Name of the AL2023 managed node group"
  type        = string
  default     = "cis-al2023-ng"
}

variable "instance_type" {
  description = "Instance type for the kube-bench node"
  type        = string
  default     = "m5.large"
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

###############################################################################
# Add-ons required by a classic (non-Auto-Mode) node: vpc-cni + kube-proxy.
# Without vpc-cni the node has no pod networking and stays NotReady
# ("cni plugin not initialized"), which fails node group creation.
###############################################################################
data "aws_eks_addon_version" "vpc_cni" {
  addon_name         = "vpc-cni"
  kubernetes_version = data.aws_eks_cluster.this.version
  most_recent        = true
}

data "aws_eks_addon_version" "kube_proxy" {
  addon_name         = "kube-proxy"
  kubernetes_version = data.aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = var.cluster_name
  addon_name                  = "vpc-cni"
  addon_version               = data.aws_eks_addon_version.vpc_cni.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = var.cluster_name
  addon_name                  = "kube-proxy"
  addon_version               = data.aws_eks_addon_version.kube_proxy.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

###############################################################################
# IAM role for the managed node group
###############################################################################
data "aws_iam_policy_document" "node_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.cluster_name}-${var.node_group_name}-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume.json
}

resource "aws_iam_role_policy_attachment" "node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    # SSM lets you shell into the node with Session Manager for interactive
    # kube-bench runs (Lab 1).
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
  ])
  policy_arn = each.value
  role       = aws_iam_role.node.name
}

###############################################################################
# AL2023 managed node group (standard EKS-optimized AL2023 AMI, nodeadm bootstrap)
###############################################################################
resource "aws_eks_node_group" "cis_al2023" {
  cluster_name    = var.cluster_name
  node_group_name = var.node_group_name
  node_role_arn   = aws_iam_role.node.arn
  # Use the cluster's own (private) subnets.
  subnet_ids     = data.aws_eks_cluster.this.vpc_config[0].subnet_ids
  ami_type       = "AL2023_x86_64_STANDARD"
  instance_types = [var.instance_type]

  scaling_config {
    min_size     = 1
    max_size     = 2
    desired_size = 1
  }

  labels = {
    "node-purpose" = "cis-benchmark"
  }

  tags = {
    "kube-bench" = "true"
  }

  # The add-ons must exist BEFORE the node launches; otherwise the node has no
  # CNI and never becomes Ready.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.vpc_cni,
    aws_eks_addon.kube_proxy,
  ]
}

output "node_group_name" {
  description = "Name of the AL2023 managed node group"
  value       = aws_eks_node_group.cis_al2023.node_group_name
}
