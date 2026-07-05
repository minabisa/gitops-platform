# Multi-Environment GitOps Deployment Platform

> A production-grade DevOps platform built on AWS — automating infrastructure provisioning, container delivery, GitOps-based deployments, and full-stack observability across three isolated environments.

---

## Overview

This project demonstrates an end-to-end DevOps platform designed to reflect real-world engineering practices used in modern cloud-native organizations. It combines infrastructure automation, CI/CD pipelines, GitOps delivery, and monitoring into a single cohesive system — built and operated entirely through code.

The platform provisions a Kubernetes cluster on AWS EKS using Terraform, automates container builds and pushes through GitHub Actions, manages multi-environment deployments via Argo CD, and provides full observability through Prometheus and Grafana.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Developer Workflow                        │
│                                                                 │
│   git push → GitHub Actions CI → AWS ECR (image registry)      │
│                    │                      │                     │
│              Tests + Scan           Image tagged               │
│                    │               with commit SHA              │
│                    └──────────────────────┘                     │
│                           Manifest updated                      │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Argo CD — GitOps Engine                     │
│                                                                 │
│         Watches repo → Detects manifest change → Syncs         │
│                                                                 │
│     ┌─────────────┬──────────────────┬─────────────────┐       │
│     │     Dev      │     Staging      │      Prod        │       │
│     │ (auto-sync) │  (auto-sync)     │  (manual sync)  │       │
│     │  namespace  │   namespace      │   namespace      │       │
│     └─────────────┴──────────────────┴─────────────────┘       │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                  AWS EKS — Kubernetes Cluster                   │
│                                                                 │
│   ┌──────────────────────────────────────────────────────┐     │
│   │                      VPC (10.0.0.0/16)               │     │
│   │                                                      │     │
│   │   Public Subnets          Private Subnets            │     │
│   │   (Load Balancers)        (Worker Nodes)             │     │
│   │                                                      │     │
│   │   Internet Gateway    NAT Gateway                    │     │
│   └──────────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Observability Stack                           │
│                                                                 │
│   Prometheus (metrics) → Grafana (dashboards + alerts)         │
│   Node Exporter (host metrics) + kube-state-metrics            │
│   Custom alerts: pod failures, crash loops, memory pressure    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| Cloud Provider | AWS | EKS, ECR, VPC, IAM, S3 |
| Infrastructure as Code | Terraform | Modular infra provisioning |
| Container Runtime | Docker | Multi-stage image builds |
| Orchestration | Kubernetes (EKS 1.35) | Container scheduling |
| GitOps Engine | Argo CD | Automated sync across environments |
| CI/CD | GitHub Actions | Build, test, scan, push pipeline |
| Manifest Management | Kustomize | Environment-specific overlays |
| Monitoring | Prometheus + Grafana | Metrics, dashboards, alerting |
| Security Scanning | Trivy | Container vulnerability scanning |
| Application | Python / Flask | Sample microservice |
| State Backend | AWS S3 | Remote Terraform state |

---

## Project Structure

```
gitops-platform/
├── .github/
│   └── workflows/
│       └── ci.yml                  # GitHub Actions CI pipeline
├── app/
│   ├── src/
│   │   └── app.py                  # Flask microservice
│   ├── tests/
│   │   └── test_app.py             # Pytest unit tests
│   ├── Dockerfile                  # Multi-stage, non-root build
│   └── requirements.txt
├── kubernetes/
│   ├── base/                       # Shared Kubernetes manifests
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── configmap.yaml
│   │   └── kustomization.yaml
│   └── overlays/                   # Per-environment patches
│       ├── dev/
│       ├── staging/
│       └── prod/
├── terraform/
│   ├── modules/
│   │   ├── vpc/                    # VPC, subnets, NAT, IGW
│   │   ├── eks/                    # EKS cluster, node group, OIDC
│   │   └── ecr/                    # Container registry + lifecycle
│   └── envs/
│       └── dev/                    # Dev environment entry point
├── monitoring/
│   └── prometheus/
│       ├── values.yaml             # Helm values for kube-prometheus-stack
│       └── pod-alerts.yaml         # Custom PrometheusRule alerts
├── docs/
│   ├── argocd-dev.yaml             # Argo CD Application — dev
│   ├── argocd-staging.yaml         # Argo CD Application — staging
│   └── argocd-prod.yaml            # Argo CD Application — prod
└── README.md
```

---

## CI/CD Pipeline — How It Works

### Continuous Integration (GitHub Actions)

Every push to `main` triggers the following pipeline:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Run Tests  │────▶│ Build Image │────▶│ Trivy Scan  │────▶│  Push ECR   │
│  (pytest)   │     │  (Docker)   │     │  (CVE scan) │     │  + Update   │
│             │     │             │     │             │     │  Manifest   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
```

**Key design decisions:**
- Tests must pass before the image is built — failures block deployment
- Images are tagged with the 7-character Git commit SHA for full traceability
- Trivy scans the built image for HIGH and CRITICAL CVEs before pushing
- The pipeline commits the new image tag back to the repo, triggering Argo CD

### Continuous Deployment (Argo CD GitOps)

Argo CD watches the GitHub repository and syncs changes automatically:

| Environment | Sync Strategy | Use Case |
|---|---|---|
| Dev | Automatic — syncs on every manifest change | Continuous delivery, rapid iteration |
| Staging | Automatic — mirrors dev after validation | Pre-release testing and QA |
| Prod | Manual sync required | Deliberate human approval gate |

**Self-healing:** If someone manually modifies a resource with `kubectl`, Argo CD detects the drift and reverts it back to the Git state within seconds.

---

## Infrastructure — Terraform Modules

All AWS infrastructure is defined as code using reusable Terraform modules.

### VPC Module
- Custom VPC with CIDR `10.0.0.0/16`
- 2 public subnets (load balancers) + 2 private subnets (worker nodes)
- Internet Gateway for public subnets
- NAT Gateway for private subnet outbound traffic
- Route tables with proper associations
- Kubernetes-specific subnet tags for EKS load balancer discovery

### EKS Module
- Managed Kubernetes control plane (v1.35)
- Dedicated IAM roles for control plane and worker nodes
- Managed node group in private subnets
- OIDC provider for pod-level IAM roles (IRSA)
- CloudWatch logging enabled for audit and API server logs
- Rolling update strategy — max 1 node unavailable at a time

### ECR Module
- Private container registry
- Automatic image scanning on push
- Lifecycle policy — retains last 10 images to control storage costs

### Remote State
- Terraform state stored in S3 with versioning and AES-256 encryption
- State locking via S3 native locking (Terraform v1.14+)
- Separate state files per environment — no cross-environment risk

---

## Monitoring & Alerting

### Stack
Installed via `kube-prometheus-stack` Helm chart:
- **Prometheus** — scrapes metrics from all namespaces including dev, staging, prod
- **Grafana** — pre-built dashboards for cluster health and pod performance
- **Alertmanager** — routes alerts based on severity
- **Node Exporter** — host-level CPU, memory, disk, network metrics
- **kube-state-metrics** — Kubernetes object state (pod counts, deployment status)

### Custom Alert Rules

| Alert | Condition | Severity |
|---|---|---|
| AppPodDown | Pod not ready for > 2 minutes in dev/staging/prod | Critical |
| AppPodCrashLooping | Container restart rate > 0 for 5 minutes | Warning |
| HighMemoryUsage | Node memory usage > 80% for 5 minutes | Warning |

### Grafana Dashboards
- **Kubernetes Cluster** — node CPU, memory, pod counts, network I/O
- **Pod Monitoring** — per-pod resource consumption across all environments

---

## Deployment — Quick Start

### Prerequisites

```bash
aws --version        # AWS CLI with credentials configured
terraform --version  # >= 1.5.0
kubectl version --client
helm version
argocd version --client
docker --version
```

### 1 — Provision Infrastructure

```bash
# Set your AWS account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create S3 backend for Terraform state
aws s3api create-bucket \
  --bucket gitops-platform-tfstate-${AWS_ACCOUNT_ID} \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket gitops-platform-tfstate-${AWS_ACCOUNT_ID} \
  --versioning-configuration Status=Enabled

# Apply infrastructure
cd terraform/envs/dev
terraform init
terraform apply
```

### 2 — Configure kubectl

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name gitops-platform-dev

kubectl get nodes
```

### 3 — Install Argo CD

```bash
kubectl create namespace argocd

kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s

# Deploy applications to all 3 environments
kubectl apply -f docs/argocd-dev.yaml
kubectl apply -f docs/argocd-staging.yaml
kubectl apply -f docs/argocd-prod.yaml
```

### 4 — Install Monitoring

```bash
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts

helm repo update

helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values monitoring/prometheus/values.yaml

kubectl apply -f monitoring/prometheus/pod-alerts.yaml
```

### 5 — Access Dashboards

```bash
# Argo CD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80

# Prometheus
kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090
```

| Dashboard | URL | Credentials |
|---|---|---|
| Argo CD | https://localhost:8080 | admin / (from k8s secret) |
| Grafana | http://localhost:3000 | admin / gitops-admin-2024 |
| Prometheus | http://localhost:9090 | — |

### 6 — Trigger a Deployment

```bash
# Any push to main triggers the full pipeline
git commit --allow-empty -m "feat: trigger pipeline"
git push origin main

# Watch Argo CD sync
argocd app list
kubectl get pods -n dev -w
```

---

## Cost Management

| Resource | Cost |
|---|---|
| EKS Control Plane | ~$0.10/hr |
| 2x t3.small nodes | ~$0.046/hr |
| NAT Gateway | ~$0.045/hr |
| ECR storage | ~$0.01/GB/month |
| **Estimated total** | **~$4.50/day** |

```bash
# Destroy when not in use
cd terraform/envs/dev
terraform destroy

# Rebuild in ~15 minutes
terraform apply
```

Since all infrastructure is code, destroying and rebuilding is fully safe — nothing is lost.

---

## Key Engineering Decisions

**Why Kustomize over Helm for app manifests?**
Kustomize is built into `kubectl`, requires no templating language, and keeps base manifests readable. Environment differences are expressed as patches rather than values — easier to audit and review.

**Why commit SHA image tags instead of `latest`?**
Every running container is traceable to a specific commit. Rolling back is a manifest update to a previous SHA — fully auditable with no ambiguity about what is deployed.

**Why manual sync for production?**
Production deployments should be intentional. Auto-sync in prod risks deploying code that passed automated checks but wasn't human-reviewed. Manual sync enforces an explicit approval step without requiring a separate tool.

**Why modular Terraform?**
Modules enforce consistency and reduce duplication. Adding a staging or prod environment reuses the same `vpc`, `eks`, and `ecr` modules with different variable values — no copy-pasting infrastructure code.

**Why S3 remote state with locking?**
Local state breaks in team environments. Remote state in S3 with locking prevents concurrent applies from corrupting infrastructure — the same pattern used in production engineering teams.

---

## Known Limitations

- Node group uses `t3.small` instances due to AWS Free Tier restrictions. Production would use `t3.large` or larger with multiple availability zones for resilience.
- A single NAT Gateway is used to reduce cost. Production would deploy one NAT Gateway per AZ for high availability.
- ECR image pull secrets are created manually per namespace. Production would use IAM Roles for Service Accounts (IRSA) for automatic, credential-free ECR access.
- Grafana persistence is disabled. Production would use an EBS-backed PersistentVolume to retain dashboard configurations across pod restarts.

---

## Author

**Mina Bisa** — DevOps Engineer

Experienced in building cloud-native platforms, CI/CD pipelines, and Kubernetes-based delivery systems across AWS environments.

- LinkedIn: [linkedin.com/in/mina-bisa](https://linkedin.com/in/mina-bisa)
- GitHub: [github.com/minabisa](https://github.com/minabisa)
- Email: Minabisa90@gmail.com

---

*Built with Terraform · Kubernetes · Argo CD · GitHub Actions · Prometheus · Grafana*
