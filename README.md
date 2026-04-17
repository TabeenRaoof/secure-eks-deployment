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

## Generating the Architecture Diagram

```bash
pip install diagrams
python docs/architecture-diagram.py
```

This generates `docs/architecture-diagram.png`.
