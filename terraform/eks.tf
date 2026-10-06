# EKS cluster + a single managed node group. Uses the official community
# module for the control plane/node-group plumbing, but control plane and
# node IAM roles are the explicit ones defined in iam.tf (create_iam_role
# = false) rather than module-generated roles.

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Public endpoint access is enabled so this student project can be
  # reached with kubectl from a local machine without a VPN/bastion.
  # In a production setup this would be restricted or disabled.
  cluster_endpoint_public_access = true

  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_cluster_role.arn

  # Creates an OIDC provider for the cluster (IAM Roles for Service
  # Accounts). Not required by the sample app, but included so the
  # project demonstrates the standard IRSA pattern.
  enable_irsa = true

  # Grants the IAM identity that runs `terraform apply` a Kubernetes
  # access entry with cluster-admin permissions, so kubectl works
  # immediately without hand-editing the aws-auth ConfigMap.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      create_iam_role = false
      iam_role_arn    = aws_iam_role.eks_node_role.arn
    }
  }

  tags = {
    Project = var.project_name
  }
}
