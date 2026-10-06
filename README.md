# End-to-End DevOps Pipeline on AWS EKS

A small but complete DevOps pipeline that takes a Python Flask app from a
git push all the way to a running pod on AWS EKS, deployed via GitOps and
monitored with Prometheus/Grafana.

Built as a portfolio project to demonstrate the **core concepts** of a
modern DevOps toolchain — not a production platform. Every piece is kept
intentionally small enough to explain in an interview.

## Objective

Show hands-on, working understanding of:

1. Infrastructure as Code (Terraform)
2. AWS networking (VPC, subnets, NAT, IAM)
3. Managed Kubernetes (EKS)
4. Containerization (Docker)
5. Kubernetes workloads (Deployments/Services)
6. Continuous Integration (GitHub Actions)
7. GitOps continuous delivery (Argo CD)
8. Basic cluster monitoring (Prometheus + Grafana)

## Architecture

```
 Developer
     │  git push
     ▼
 GitHub repo ───────────────────────────────┐
     │                                       │
     │ triggers                              │ watched by
     ▼                                       ▼
 GitHub Actions (CI)                     Argo CD (GitOps)
     │  build + test                         │  detects k8s/ changes
     │  docker build & push                  │  auto sync + prune + selfHeal
     ▼                                       ▼
 GHCR (container registry)  <───pulls─── EKS worker nodes
                                               │
                                               ▼
                                   ┌───────────────────────┐
                                   │   AWS EKS Cluster      │
                                   │  (private subnets)     │
                                   │                         │
                                   │  Deployment (2 pods)    │
                                   │        │                │
                                   │  Service (LoadBalancer) │
                                   └───────────┬────────────┘
                                               │ scraped by
                                               ▼
                                  Prometheus + Grafana
                                     (kube-prometheus-stack)
```

```
            ┌───────────────────── VPC (10.0.0.0/16) ─────────────────────┐
            │                                                              │
            │   Public subnets (2 AZs)        Private subnets (2 AZs)     │
            │   ┌─────────────┐                ┌─────────────────────┐   │
            │   │ NAT Gateway │───────────────▶│  EKS worker nodes    │   │
            │   │     IGW     │                │  (managed node grp)  │   │
            │   └─────────────┘                └─────────────────────┘   │
            └──────────────────────────────────────────────────────────┘
                                   EKS control plane (AWS-managed)
```

## Technologies used

| Layer | Tool |
|---|---|
| IaC | Terraform (AWS provider, S3 + DynamoDB remote state) |
| Cloud | AWS (VPC, EKS, IAM, S3, DynamoDB) |
| Containers | Docker |
| Orchestration | Kubernetes (EKS) |
| CI | GitHub Actions |
| GitOps / CD | Argo CD |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack via Helm) |
| App | Python Flask |

## Project structure

```
.
├── terraform/
│   ├── bootstrap/            # one-time: creates S3 state bucket + DynamoDB lock table
│   ├── provider.tf
│   ├── versions.tf            # required_version + backend "s3" {}
│   ├── variables.tf
│   ├── vpc.tf                 # VPC, public/private subnets, NAT
│   ├── iam.tf                 # explicit EKS cluster + node IAM roles
│   ├── eks.tf                 # EKS cluster + managed node group
│   ├── outputs.tf
│   └── README.md              # backend bootstrap instructions
├── app/
│   ├── app.py                 # Flask app: GET / and GET /health
│   ├── test_app.py
│   ├── requirements.txt
│   └── Dockerfile
├── k8s/
│   ├── deployment.yaml         # 2 replicas, probes on /health
│   └── service.yaml            # LoadBalancer Service
├── argocd/
│   └── application.yaml        # Argo CD Application (automated sync/prune/selfHeal)
├── monitoring/
│   └── values.yaml              # minimal kube-prometheus-stack overrides
├── .github/workflows/ci.yml      # test -> build -> push to GHCR
├── .gitignore
└── README.md
```

## How Terraform works here

- `terraform/bootstrap` is a **separate** Terraform project with no remote
  backend (it uses local state) because it creates the S3 bucket +
  DynamoDB table that the *main* project's backend depends on. This avoids
  a circular dependency — you can't store state in a bucket that doesn't
  exist yet.
- The main project (`terraform/`) declares `backend "s3" {}` with the
  actual bucket/key/table supplied at `terraform init` time via
  `-backend-config=backend.hcl` (backend blocks can't use variables).
- State locking is handled by a DynamoDB table (`LockID` hash key),
  preventing two people/pipelines from running `apply` at the same time.
- See `terraform/README.md` for exact bootstrap commands.

## How EKS is created

- `vpc.tf` uses the `terraform-aws-modules/vpc/aws` module to build a VPC
  with 2 public subnets (NAT gateway, internet-facing load balancers) and
  2 private subnets (EKS worker nodes — no direct internet exposure).
- `iam.tf` hand-defines two IAM roles rather than letting a module
  auto-generate them:
  - **Cluster role** — trusted by `eks.amazonaws.com`, with
    `AmazonEKSClusterPolicy` attached.
  - **Node role** — trusted by `ec2.amazonaws.com`, with
    `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and
    `AmazonEC2ContainerRegistryReadOnly` attached.
- `eks.tf` uses the `terraform-aws-modules/eks/aws` module for the
  control plane + one managed node group (2–3 `t3.medium` nodes),
  passing in the explicit roles above (`create_iam_role = false`).
- The cluster's public API endpoint is enabled so `kubectl` works from a
  local machine without a bastion/VPN — acceptable for a demo cluster,
  would be restricted in production.

## How GitHub Actions works

`.github/workflows/ci.yml` triggers on push to `main` (when `app/**`
changes):

1. **test** job — checks out code, installs Flask, runs `pytest` against
   `app/test_app.py`.
2. **build-and-push** job (depends on `test` passing) — logs into GHCR
   using the built-in `GITHUB_TOKEN` (no manual secret needed), builds
   the Docker image, and pushes it tagged with both the commit SHA and
   `latest`.

No Docker Hub credentials are required by default. If you'd rather push
to Docker Hub, swap the `docker/login-action` step to use
`secrets.DOCKERHUB_USERNAME` / `secrets.DOCKERHUB_TOKEN` and set those as
repository secrets under **Settings → Secrets and variables → Actions**
— never paste credentials into chat or commit them.

## How Argo CD works

- `argocd/application.yaml` defines one Argo CD `Application` that
  watches the `k8s/` folder of this repo on the `main` branch.
- `syncPolicy.automated` has `prune: true` and `selfHeal: true`: Argo CD
  automatically applies new commits to `k8s/`, deletes resources removed
  from Git, and reverts any manual `kubectl` drift back to match Git.
- Flow: `git push` → Argo CD detects the diff → syncs the Deployment/
  Service → pods roll out on EKS.

## How monitoring works

- `kube-prometheus-stack` (Helm chart) installs Prometheus, Grafana,
  Alertmanager, and the node-exporter/kube-state-metrics exporters that
  feed them — this is the standard "batteries included" way to get
  cluster metrics without hand-wiring scrape configs.
- Grafana ships with default Kubernetes dashboards out of the box; no
  custom dashboards were built for this project (by design — the goal is
  demonstrating the pipeline, not dashboard design).
- Access is via `kubectl port-forward` (see Useful commands) rather than
  a public LoadBalancer, since this is a local-access demo setup.

## Setup instructions

### Prerequisites
`terraform`, `aws` (authenticated), `kubectl`, `docker`, `git`, `helm`, `gh`

### 1. Bootstrap Terraform remote state
```bash
cd terraform/bootstrap
cp terraform.tfvars.example terraform.tfvars   # set a unique state_bucket_name
terraform init
terraform apply
```

### 2. Provision the VPC + EKS cluster
```bash
cd ../
cp backend.hcl.example backend.hcl             # fill in bucket/table from step 1
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

### 3. Point kubectl at the new cluster
```bash
aws eks update-kubeconfig --region us-east-1 --name eks-devops-cluster
kubectl get nodes
```

### 4. Build & push the app image (or let GitHub Actions do it)
```bash
cd app
docker build -t ghcr.io/<you>/eks-devops-app:latest .
docker push ghcr.io/<you>/eks-devops-app:latest
```

### 5. Deploy with kubectl (first time) or Argo CD (ongoing)
```bash
kubectl apply -f k8s/deployment.yaml -f k8s/service.yaml
kubectl get pods,svc
```

### 6. Install Argo CD and the Application
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f argocd/application.yaml
```

### 7. Install Prometheus + Grafana
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/values.yaml
```

## Useful commands

```bash
# Cluster
kubectl get nodes
kubectl get pods -A
kubectl get deployments,svc

# App
kubectl logs -l app=eks-devops-app
kubectl port-forward svc/eks-devops-app 8080:80
curl localhost:8080/  && curl localhost:8080/health

# Argo CD UI
kubectl port-forward svc/argocd-server -n argocd 8081:443
# https://localhost:8081  (user: admin, password: see below)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

# Grafana UI
kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80
# http://localhost:3000  (user: admin, password: admin — see monitoring/values.yaml)
```

## Screenshots / evidence to capture

- `aws sts get-caller-identity` output
- `terraform plan` / `terraform apply` summary (resources created)
- `kubectl get nodes` showing 2 Ready EKS nodes
- `kubectl get pods,svc` showing the app running with 2/2 pods
- `curl` output from `/` and `/health`
- GitHub Actions run showing green checkmarks (test → build-and-push)
- GHCR package page showing the pushed image
- Argo CD UI showing the Application as **Synced / Healthy**
- A diff commit to `k8s/deployment.yaml` + Argo CD auto-syncing it
- Grafana dashboard showing live cluster CPU/memory metrics

## Cleanup (avoid ongoing AWS charges)

```bash
# Remove Helm releases and Argo CD first (so LBs/PVs they created are cleaned up)
helm uninstall monitoring -n monitoring
kubectl delete -f argocd/application.yaml
kubectl delete namespace argocd

# Remove the app
kubectl delete -f k8s/service.yaml -f k8s/deployment.yaml

# Destroy the EKS cluster/VPC
cd terraform
terraform destroy

# Only if you no longer need remote state at all:
cd bootstrap
terraform destroy
```

The EKS control plane, EC2 nodes, and NAT gateway bill **by the hour**
whether or not anything is deployed on them — run `terraform destroy`
when you're done experimenting.
