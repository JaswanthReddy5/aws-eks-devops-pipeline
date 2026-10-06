terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend (S3 + DynamoDB lock table).
  # These values are intentionally left blank here and supplied at
  # `terraform init` time via -backend-config=backend.hcl, because
  # backend blocks cannot reference variables.
  #
  # Run the bootstrap project in terraform/bootstrap/ FIRST to create
  # the bucket and table, then copy backend.hcl.example -> backend.hcl
  # and fill in the values it outputs. See terraform/README.md.
  backend "s3" {}
}
