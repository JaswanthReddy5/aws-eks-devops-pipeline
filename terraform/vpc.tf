# VPC with public subnets (for the NAT gateway / load balancers) and
# private subnets (for EKS worker nodes). Uses the official community
# module instead of hand-rolled resources to avoid re-implementing
# well-tested routing/NAT logic — a single NAT gateway is used to keep
# cost down, which is fine for a learning/demo cluster.

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = var.azs
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Required tags so the EKS and AWS Load Balancer Controller know which
  # subnets to use for internal vs internet-facing load balancers.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = {
    Project = var.project_name
  }
}
