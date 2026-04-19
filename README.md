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
├── docs/                          # Architecture documentation
│   ├── architecture-design.md     # Phase 1: Design and security justification
│   └── architecture-diagram.py    # Generates architecture diagram (requires diagrams lib)
├── terraform/                     # Phase 2: Infrastructure as Code
│   ├── main.tf                    # Root module — wires all modules together
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Cluster outputs
│   ├── versions.tf                # Provider version constraints
│   ├── terraform.tfvars.example   # Example variable values (copy to terraform.tfvars)
│   └── modules/
│       ├── vpc/                   # VPC, subnets, NAT, flow logs
│       ├── iam/                   # IAM roles, IRSA setup
│       ├── security/              # Security groups, NACLs, KMS
│       └── eks/                   # EKS cluster, node group, OIDC
├── kubernetes/                    # Kubernetes manifests (Phase 3+)
│   └── README.md                  # Guide for application deployment
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

## Deployment Instructions (Phase 2)

### Step 1: Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values. At minimum, update `public_access_cidrs` to restrict API access to your team's IPs:

```hcl
public_access_cidrs = ["YOUR.IP.ADDRESS/32"]
```

### Step 2: Initialize Terraform

```bash
terraform init
```

### Step 3: Review the Plan

```bash
terraform plan
```

Review the output carefully. You should see approximately 25-30 resources to be created (VPC, subnets, NAT, IGW, EKS cluster, node group, IAM roles, security groups, NACLs, KMS key, flow logs).

### Step 4: Deploy

```bash
terraform apply
```

Type `yes` when prompted. Deployment takes approximately 15-20 minutes (EKS cluster creation is the longest step).

### Step 5: Configure kubectl

After deployment completes, configure `kubectl` to connect to your cluster:

```bash
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev
```

Verify the connection:

```bash
kubectl get nodes
kubectl cluster-info
```

You should see your managed node group nodes in `Ready` status.

## Post-Deployment Verification

Run these commands to verify the security configuration:

```bash
# Verify nodes are in private subnets (no public IPs)
kubectl get nodes -o wide

# Verify cluster info
aws eks describe-cluster --name fintech-secure-dev --query 'cluster.{Endpoint:endpoint,Version:version,Logging:logging,EncryptionConfig:encryptionConfig}'

# Verify VPC Flow Logs are active
aws ec2 describe-flow-logs --filter "Name=tag:Project,Values=fintech-secure"
```

## Cost Estimate

Approximate monthly cost for the default configuration:

| Resource | Estimated Cost |
|----------|---------------|
| EKS Cluster | $73/month |
| EC2 (2x t3.medium) | ~$60/month |
| NAT Gateway | ~$32/month + data |
| CloudWatch Logs | ~$5/month |
| KMS Key | ~$1/month |
| **Total** | **~$171/month** |

**Important**: Remember to run `terraform destroy` when you're done to avoid ongoing charges.

## Teardown

To destroy all resources:

```bash
cd terraform
terraform destroy
```

Type `yes` when prompted. This removes all AWS resources created by Terraform.

---

## Phase 6 Quick Start (Data Security)

This repository includes baseline Phase 6 assets:

- Terraform-managed Secrets Manager secret container (`fintech-secure-dev-backend`)
- IRSA role policy scoped to the backend secret
- Backend config support for Secrets Manager (`APP_SECRETS_NAME`)
- HTTPS ingress template with ACM annotations in `kubernetes/ingress/app-ingress-acm.yaml`

See the full runbook in [`docs/phase6-data-security.md`](docs/phase6-data-security.md).

If you are hosting frontend on Vercel without a custom domain yet, use:

- Frontend env: `VITE_API_URL=http://<eks-alb-dns>/api`
- Backend secret: `CORS_ORIGINS=https://<your-vercel-domain>`

This allows a working split deployment (Vercel frontend + EKS backend) while keeping the ACM-based TLS ingress configuration ready for a custom domain later.

---

## Team Responsibilities — Next Phases

### Phase 3: Application Deployment 

Deploy the multi-tier application into the EKS cluster:
- Frontend (React or static web)
- Backend API (Node.js or Python/Flask)
- Database (RDS PostgreSQL or containerized)
- Use Kubernetes Deployments, Services, and Ingress
- See [`kubernetes/README.md`](kubernetes/README.md) for details

### Phase 4: Identity & Access Management 

- Configure Kubernetes RBAC (Roles, RoleBindings)
- Set up IRSA for application pods (foundation already in `terraform/modules/iam/`)
- Implement `aws-auth` ConfigMap for cluster access control

### Phase 5: Network Security 

- Apply Kubernetes Network Policies to restrict pod-to-pod communication
- Review and tighten Security Group rules based on actual traffic patterns
- Test network isolation between frontend, backend, and database pods

### Phase 6: Data Security 

- Configure TLS/HTTPS for the application (cert-manager + Let's Encrypt or ACM)
- Store application secrets in AWS Secrets Manager
- Verify encryption at rest is active for EBS and any RDS instances

### Phase 7: Container Security 

- Set up Amazon ECR with image scanning
- Scan images with Trivy in CI/CD
- Enforce Pod Security Standards (restricted profile)
- Ensure all containers run as non-root with read-only root filesystems

### Phase 8: Monitoring & Logging 

- Enable CloudWatch Container Insights
- Optionally deploy Prometheus + Grafana
- Enable AWS GuardDuty for threat detection
- Set up CloudWatch alarms for critical metrics

### Phase 9: Threat Simulation (Both)

Simulate at least 2 security scenarios:
1. Unauthorized access attempt (e.g., access forbidden namespace)
2. Pod compromise / privilege escalation attempt

Document detection, mitigation, and incident response for each.

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
