# Terraform — Remote State Bootstrap + Main Infrastructure

This project uses a **remote S3 backend with DynamoDB state locking**.
To avoid a chicken-and-egg problem (Terraform can't store state in an
S3 bucket that doesn't exist yet), the backend infrastructure is created
by a small, separate "bootstrap" Terraform project that uses **local**
state.

## Step 1 — Bootstrap the backend (one-time)

```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars — set a globally-unique state_bucket_name

terraform init
terraform plan
terraform apply
```

This creates:
- An S3 bucket (versioned + AES256 encrypted + public access blocked) to store `terraform.tfstate`
- A DynamoDB table (`eks-devops-tf-lock` by default) used for state locking

Note the `state_bucket_name` and `lock_table_name` outputs.

## Step 2 — Point the main project at that backend

```bash
cd ../           # back to terraform/
cp backend.hcl.example backend.hcl
# edit backend.hcl with the bucket/table names from step 1

cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if you want to change region/sizes

terraform init -backend-config=backend.hcl
terraform fmt
terraform validate
terraform plan
```

Review the plan. Only run `terraform apply` once you're ready to create
real AWS resources (EKS billing starts immediately — see the root
README's cost section).

## Why two separate projects?

- `bootstrap/` has no backend block — it stores state locally, since
  nothing else is set up yet.
- `terraform/` (the main project) has `backend "s3" {}` in `versions.tf`
  with the actual bucket/key/region/table supplied via
  `-backend-config=backend.hcl` at init time (backend blocks cannot
  reference variables).

`backend.hcl` and `terraform.tfvars` are gitignored since they contain
account-specific (not secret, but environment-specific) values.
