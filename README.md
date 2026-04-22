# Secure Cloud-Native Application Deployment on AWS EKS

Design, implementation, and security hardening of a cloud-native fintech application on AWS EKS.

## Project Overview

This project deploys a secure, multi-tier microservices application on Amazon Elastic Kubernetes Service (EKS) with comprehensive security controls at every layer — network, identity, data, container, and runtime.

### Architecture Highlights

- **VPC** with public/private subnet separation across 3 Availability Zones
- **EKS cluster** with managed node groups in private subnets (no public IPs)
- **IAM** least-privilege roles with IRSA for pod-level permissions
- **KMS** customer-managed key for secrets encryption at rest
- **VPC Flow Logs** and **CloudWatch** for security auditing
- **Security Groups + NACLs** for defense-in-depth network security

For the full architecture design and security justification, see [`docs/architecture-design.md`](docs/architecture-design.md).

## Repository Structure

```
├── backend/                        # Flask API (Python)
│   ├── Dockerfile                  # Hardened, multi-stage, non-root (UID 1000)
│   └── app/                        # Application code
├── frontend/                       # React + nginx
│   ├── Dockerfile                  # Multi-stage, nginx-unprivileged (UID 101)
│   └── src/                        # Application code
├── docs/                           # Documentation
│   ├── architecture-design.md      # Phase 1
│   ├── architecture-diagram.py     # Diagram generator
│   ├── phase4-iam-rbac.md          # Phase 4
│   ├── phase6-data-security.md     # Phase 6
│   ├── phase7-container-security.md  # Phase 7
│   ├── phase8-monitoring-logging.md  # Phase 8
│   ├── phase9-threat-simulation.md   # Phase 9
│   └── technical-report.md         # 10-15 page consolidated report
├── terraform/                      # Infrastructure as Code
│   ├── main.tf                     # Root — wires all modules together
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       ├── vpc/                    # VPC, subnets, NAT, flow logs
│       ├── iam/                    # IAM roles, IRSA, RBAC personas
│       ├── security/               # Security groups, NACLs, KMS
│       ├── eks/                    # EKS cluster, nodes, OIDC
│       ├── container-security/     # ECR with scan-on-push + enhanced scanning
│       └── monitoring/             # GuardDuty, CloudWatch alarms, Container Insights
├── kubernetes/                     # Kubernetes manifests
│   ├── namespaces/                 # fintech-app, monitoring (with PSS labels)
│   ├── rbac/                       # ClusterRoles, Roles, Bindings, aws-auth, SAs
│   ├── deployments/                # frontend, backend, postgres
│   ├── services/                   # ClusterIP services
│   ├── ingress/                    # ALB ingress with ACM TLS
│   ├── network-policies/           # Default-deny + tier-to-tier allow
│   └── monitoring/                 # Prometheus/Grafana Helm values
├── .github/workflows/              # CI/CD
│   ├── trivy-scan.yml              # Scans source, images, k8s manifests
│   └── build-and-push.yml          # Builds + pushes to ECR via OIDC
└── .gitignore
```

## Prerequisites

Install the following tools before proceeding:

| Tool | Version | Purpose |
|------|---------|---------|
| [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) | v2.x | AWS resource management |
| [Terraform](https://developer.hashicorp.com/terraform/downloads) | >= 1.5.0 | Infrastructure provisioning |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | v1.29.x | Kubernetes cluster management |
| [aws-iam-authenticator](https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html) | latest | EKS authentication |

### AWS Account Setup

1. Create an AWS account or use an existing one
2. Create an IAM user with programmatic access and the following policies:
   - `AmazonEKSClusterPolicy`
   - `AmazonEKSServicePolicy`
   - `AmazonVPCFullAccess`
   - `IAMFullAccess`
   - `AmazonEC2FullAccess`
   - `CloudWatchFullAccess`
   - `AWSKeyManagementServicePowerUser`
3. Configure AWS CLI:
   ```bash
   aws configure
   # Enter your Access Key ID, Secret Access Key, region (us-west-2), and output format (json)
   ```

## Full Deployment Guide

End-to-end deployment is a three-part process:

1. **Infrastructure** — Terraform provisions AWS resources (~15-20 min)
2. **Container images** — Build and push to ECR via CI/CD or manually
3. **Kubernetes workloads** — `kubectl apply` the manifests in order

### Part 1 — Infrastructure (Terraform)

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - set public_access_cidrs to YOUR IP (e.g. ["203.0.113.5/32"])
#   - set alarm_email if you want CloudWatch alarm notifications
terraform init
terraform plan      # review ~50 resources
terraform apply     # ~15-20 min (EKS cluster is the long pole)
```

Once complete, configure kubectl:

```bash
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev
kubectl get nodes   # should show 2 Ready nodes
```

### Part 2 — Build and Push Container Images

**Option A — GitHub Actions (recommended)**

Configure one secret in your GitHub repo: `AWS_GHA_ROLE_ARN` (an IAM role trusted by GitHub OIDC with `AmazonEC2ContainerRegistryPowerUser`). Then:

```bash
git push origin main    # triggers .github/workflows/build-and-push.yml
```

The workflow builds both images, runs a Trivy CRITICAL-severity gate, and pushes to ECR.

**Option B — Manual**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com

# Backend
docker build -t $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/backend:latest ./backend
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/backend:latest

# Frontend
docker build -t $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/frontend:latest ./frontend
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/frontend:latest
```

### Part 3 — Kubernetes Workloads

Install the AWS Load Balancer Controller first (required for the ALB Ingress):

```bash
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=fintech-secure-dev
```

Update placeholders in the manifests (`<ACCOUNT_ID>`, `<CERTIFICATE_ID>`):

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
grep -rl '<ACCOUNT_ID>' kubernetes/ | xargs sed -i.bak "s/<ACCOUNT_ID>/$ACCOUNT_ID/g"
```

Then apply manifests in order (details in [`kubernetes/README.md`](kubernetes/README.md)):

```bash
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/rbac/
kubectl apply -f kubernetes/deployments/postgres.yaml
kubectl apply -f kubernetes/deployments/backend.yaml
kubectl apply -f kubernetes/deployments/frontend.yaml
kubectl apply -f kubernetes/services/
kubectl apply -f kubernetes/ingress/
kubectl apply -f kubernetes/network-policies/
```

### Post-Deployment Verification

```bash
# Nodes in private subnets, no public IPs
kubectl get nodes -o wide

# All pods running and Ready
kubectl get pods -n fintech-app

# Ingress provisioned with ALB
kubectl get ingress -n fintech-app

# Network Policies active
kubectl get networkpolicy -n fintech-app

# GuardDuty enabled with EKS audit log monitoring
aws guardduty list-detectors

# Alarms armed
aws cloudwatch describe-alarms --alarm-name-prefix fintech-secure-dev
```

## Cost Estimate

Approximate monthly cost for the default configuration:

| Resource | Estimated Cost |
|----------|---------------|
| EKS Cluster | $73/month |
| EC2 (2x t3.medium) | ~$60/month |
| NAT Gateway | ~$32/month + data |
| CloudWatch Logs + Container Insights | ~$10/month |
| GuardDuty (EKS protection) | ~$30/month |
| ECR (10GB) | ~$1/month |
| KMS Key | ~$1/month |
| **Total** | **~$210/month** |

**Important**: Remember to run `terraform destroy` when you're done to avoid ongoing charges.

## Teardown

```bash
# Remove Kubernetes resources first so the ALB and node group drain cleanly
kubectl delete -f kubernetes/network-policies/ -f kubernetes/ingress/ -f kubernetes/services/ -f kubernetes/deployments/ --ignore-not-found

# Then destroy AWS infrastructure
cd terraform
terraform destroy
```

---

## Phase Implementation Status

| # | Phase | Status | Key Artifacts |
|---|-------|--------|--------------|
| 1 | Architecture Design | Complete | [`docs/architecture-design.md`](docs/architecture-design.md) |
| 2 | EKS Cluster Deployment | Complete | [`terraform/`](terraform/) |
| 3 | Application Deployment | Complete | [`kubernetes/deployments/`](kubernetes/deployments/), [`kubernetes/services/`](kubernetes/services/) |
| 4 | Identity & Access Management | Complete | [`docs/phase4-iam-rbac.md`](docs/phase4-iam-rbac.md), [`kubernetes/rbac/`](kubernetes/rbac/) |
| 5 | Network Security | Complete | [`kubernetes/network-policies/`](kubernetes/network-policies/), [`terraform/modules/security/`](terraform/modules/security/) |
| 6 | Data Security | Complete | [`docs/phase6-data-security.md`](docs/phase6-data-security.md), [`kubernetes/ingress/`](kubernetes/ingress/) |
| 7 | Container Security | Complete | [`docs/phase7-container-security.md`](docs/phase7-container-security.md), [`terraform/modules/container-security/`](terraform/modules/container-security/), [`.github/workflows/trivy-scan.yml`](.github/workflows/trivy-scan.yml) |
| 8 | Monitoring & Logging | Complete | [`docs/phase8-monitoring-logging.md`](docs/phase8-monitoring-logging.md), [`terraform/modules/monitoring/`](terraform/modules/monitoring/) |
| 9 | Threat Simulation | Complete | [`docs/phase9-threat-simulation.md`](docs/phase9-threat-simulation.md), [`docs/eks_security_report_final.pdf`](docs/eks_security_report_final.pdf) |

---

## Contributing — Git Workflow Guide

This section walks you through the full Git workflow for contributing to this project, from forking to getting your changes merged. No prior Git experience is assumed.

### One-Time Setup

#### 1. Fork the Repository

A **fork** is your own personal copy of the repository on GitHub.

1. Go to the project's GitHub page.
2. Click the **Fork** button (top-right corner).
3. GitHub will create a copy under your account (e.g., `github.com/YOUR-USERNAME/secure-eks-deployment`).

#### 2. Clone Your Fork Locally

This downloads your fork to your computer so you can work on it.

```bash
git clone https://github.com/YOUR-USERNAME/secure-eks-deployment.git
cd secure-eks-deployment
```

#### 3. Add the Original Repo as "upstream"

This lets you pull in updates from the main project later.

```bash
git remote add upstream https://github.com/ORIGINAL-OWNER/secure-eks-deployment.git
```

Verify both remotes are set up:

```bash
git remote -v
# origin    https://github.com/YOUR-USERNAME/secure-eks-deployment.git (fetch)
# origin    https://github.com/YOUR-USERNAME/secure-eks-deployment.git (push)
# upstream  https://github.com/ORIGINAL-OWNER/secure-eks-deployment.git (fetch)
# upstream  https://github.com/ORIGINAL-OWNER/secure-eks-deployment.git (push)
```

### Making Changes

#### 4. Keep Your Local Copy Up to Date

Before starting any new work, always sync with the latest changes from the main project:

```bash
git checkout main
git fetch upstream
git merge upstream/main
git push origin main
```

#### 5. Create a New Branch

Never work directly on `main`. Create a descriptive branch for each piece of work:

```bash
git checkout -b feature/your-feature-name
```

Use prefixes to categorize your branch:
- `feature/` — new functionality (e.g., `feature/add-monitoring`)
- `fix/` — bug fixes (e.g., `fix/security-group-rule`)
- `docs/` — documentation changes (e.g., `docs/update-readme`)

#### 6. Make Your Changes

Edit files as needed using your editor or IDE. When you're done, check what changed:

```bash
git status           # see which files were modified/added
git diff             # see the exact line-by-line changes
```

#### 7. Stage and Commit

**Staging** selects which changes to include in your next commit.

```bash
git add file1.tf file2.tf       # stage specific files
# or
git add .                       # stage all changes in the current directory
```

**Commit** saves the staged changes with a descriptive message:

```bash
git commit -m "Add CloudWatch alarms for EKS node CPU usage"
```

Tips for good commit messages:
- Start with a verb: *Add*, *Fix*, *Update*, *Remove*, *Refactor*
- Keep the first line under 72 characters
- Describe **what** and **why**, not *how*

#### 8. Push Your Branch to GitHub

```bash
git push origin feature/your-feature-name
```

If this is your first push on the branch, Git will create it on your fork automatically.

### Getting Your Changes Merged

#### 9. Open a Pull Request (PR)

1. Go to your fork on GitHub.
2. You'll see a banner saying your branch was recently pushed — click **Compare & pull request**.
3. Fill in the PR template:
   - **Title**: A short summary of the change.
   - **Description**: What you changed and why. Reference any related issues (e.g., "Closes #12").
4. Click **Create pull request**.

#### 10. Respond to Code Review Feedback

Team members may leave comments or request changes. To make updates:

```bash
# Make the requested changes in your editor, then:
git add .
git commit -m "Address review feedback: tighten SG ingress rules"
git push origin feature/your-feature-name
```

The PR updates automatically — no need to open a new one.

### Useful Day-to-Day Commands

| Command | What It Does |
|---------|-------------|
| `git status` | Show modified, staged, and untracked files |
| `git log --oneline -10` | Show the last 10 commits in a compact format |
| `git diff` | Show unstaged changes |
| `git diff --staged` | Show staged changes (what will be committed) |
| `git branch` | List all local branches |
| `git branch -d branch-name` | Delete a local branch you're done with |
| `git stash` | Temporarily save uncommitted changes |
| `git stash pop` | Restore the most recently stashed changes |
| `git pull origin main` | Pull latest changes from your fork's main branch |

### Handling Common Situations

#### Undo the Last Commit (Keep Changes)

If you committed too early or with the wrong message:

```bash
git reset --soft HEAD~1
```

Your changes stay staged so you can re-commit.

#### Resolve Merge Conflicts

If your branch has conflicts with `main`:

```bash
git checkout main
git pull upstream main
git checkout feature/your-feature-name
git merge main
```

Git will mark conflicts in the affected files. Open them, look for the conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`), choose the correct code, then:

```bash
git add .
git commit -m "Resolve merge conflicts with main"
git push origin feature/your-feature-name
```

#### Accidentally Committed to main

If you made changes on `main` instead of a branch:

```bash
git branch feature/my-accidental-work    # save your commits to a new branch
git checkout main
git reset --hard upstream/main           # reset main to match upstream
git checkout feature/my-accidental-work  # switch to your new branch and continue
```

### Best Practices

- **Pull before you push** — always sync with upstream before starting new work.
- **One branch per feature/fix** — keeps PRs small and easy to review.
- **Write meaningful commit messages** — your future self (and teammates) will thank you.
- **Don't commit secrets** — never commit AWS keys, `.tfvars` files with real values, or `.env` files. These are already in `.gitignore`.
- **Test before pushing** — run `terraform validate` and `terraform plan` for any infrastructure changes.

---

## Generating the Architecture Diagram

```bash
pip install diagrams
python docs/architecture-diagram.py
```

This generates `docs/architecture-diagram.png`.
