# Demo & Deployment Plan

This document covers both:

1. **Deployment rehearsal plan** — the sequence of steps to get the cluster working before demo day
2. **Demo video plan** — the 10–15 minute recording structure with timing and commands

---

## Part A — Deployment Rehearsal (Do This Before Recording)

### Prerequisites on the Recording Machine

Install these tools and verify each works:

| Tool | Check |
|------|-------|
| AWS CLI v2 | `aws --version` |
| Terraform ≥ 1.5 | `terraform version` |
| kubectl v1.29 | `kubectl version --client` |
| Helm 3 | `helm version` |
| Docker | `docker --version` |
| jq | `jq --version` |

Configure AWS credentials and confirm:

```bash
aws sts get-caller-identity
```

### Full Dry-Run (Before Recording)

Do this **at least once** end to end so nothing surprises you on camera. Expect it to take ~45 minutes including image builds.

```bash
# 1. Provision infrastructure (~15-20 min)
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   - public_access_cidrs = ["<YOUR.IP.0.0/32>"]
#   - alarm_email = "<your-email>"
terraform init
terraform apply -auto-approve

# 2. Connect kubectl
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev
kubectl get nodes   # must show 2 Ready nodes

# 3. Install AWS Load Balancer Controller (required for Ingress)
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system --set clusterName=fintech-secure-dev

# 4. Substitute <ACCOUNT_ID> placeholders
cd ..
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
grep -rl '<ACCOUNT_ID>' kubernetes/ | xargs sed -i.bak "s/<ACCOUNT_ID>/$ACCOUNT_ID/g"

# 5. Build and push images
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com

docker build -t $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/backend:latest ./backend
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/backend:latest

docker build -t $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/frontend:latest ./frontend
docker push $ACCOUNT_ID.dkr.ecr.us-west-2.amazonaws.com/fintech-secure/frontend:latest

# 6. Apply Kubernetes manifests in order
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/rbac/
kubectl apply -f kubernetes/deployments/postgres.yaml
kubectl apply -f kubernetes/deployments/backend.yaml
kubectl apply -f kubernetes/deployments/frontend.yaml
kubectl apply -f kubernetes/services/
kubectl apply -f kubernetes/ingress/   # edit cert ARN first if using custom domain
kubectl apply -f kubernetes/network-policies/

# 7. Verify everything is running
kubectl get pods -n fintech-app
kubectl get svc -n fintech-app
kubectl get ingress -n fintech-app

# 8. Tear down when dry-run done
kubectl delete -f kubernetes/network-policies/ -f kubernetes/ingress/ \
               -f kubernetes/services/        -f kubernetes/deployments/ \
               --ignore-not-found
cd terraform && terraform destroy -auto-approve
```

### Pre-Recording Checklist

- [ ] Full dry-run completed successfully
- [ ] All verification commands tested and produce clean output
- [ ] Threat simulation commands tested (RBAC denial + PSS denial)
- [ ] Architecture diagram PNG rendered (`python docs/architecture-diagram.py`)
- [ ] Screen recording software tested (OBS Studio, QuickTime, or Loom)
- [ ] Microphone level checked
- [ ] Terminal font size bumped to ≥ 16pt for readability
- [ ] Two terminal tabs open: one for `aws` / `terraform`, one for `kubectl`
- [ ] Browser tabs ready: AWS Console (CloudWatch, GuardDuty, ECR), Architecture diagram, `docs/technical-report.md`

### Recording Day Setup

- Re-provision the cluster ~30 min before recording
- Pre-build and push images so `kubectl apply` lands quickly
- Pause any IDE auto-save / chat notifications
- Close personal tabs / tools with PII
- Have a text file open with the commands you'll type — **do not type from memory**

---

## Part B — Demo Video Plan (10–15 min)

### Shape of the Video

| Section | Length | Purpose |
|---------|--------|---------|
| 1. Intro + problem statement | 0:45 | Who, what, why |
| 2. Architecture overview | 1:30 | Diagram walkthrough |
| 3. Deployment process | 3:30 | Terraform → kubectl (fast-forward) |
| 4. Security configurations | 4:00 | Walk through each layer live |
| 5. Threat simulation | 3:30 | Two attacks, live denial + alert |
| 6. Wrap-up + cost awareness | 1:00 | Summary + `terraform destroy` |
| **Total** | **~14:00** | |

### Section 1 — Intro (0:00–0:45)

On-screen: title slide.

Script outline:
- "Hi, I'm [name]. This is our CS581 Signature Project — a secure, multi-tier fintech application deployed on AWS EKS."
- "Our goal is to demonstrate defense in depth: every layer — network, identity, data, container, runtime, monitoring — has its own security control."
- "In the next fourteen minutes I'll walk you through the architecture, deploy the full stack, show the security configurations live, and run two threat simulations."

### Section 2 — Architecture Overview (0:45–2:15)

On-screen: architecture diagram (image, not code).

Talking points:
- VPC with three AZs, public subnets for ALB and NAT, private subnets for EKS nodes
- EKS cluster with managed node group — **nodes have no public IPs**
- IAM with three personas, IRSA for pod-level AWS access
- KMS encrypts EBS, EKS secrets, Secrets Manager, ECR, SNS
- CloudWatch + GuardDuty for observability and threat detection

### Section 3 — Deployment Process (2:15–5:45)

**Pre-recorded tip**: The 15-minute `terraform apply` should be **fast-forwarded** in the edit. Recording live takes too long.

#### 3a. Terraform plan (live, ~30s)

```bash
cd terraform
terraform plan | tail -20
```

Point out: "Roughly fifty resources. Everything from VPC to KMS to GuardDuty is declarative."

#### 3b. Apply (fast-forwarded, ~1 min of video)

Start recording `terraform apply`, then cut the video to show only:
- Start of apply
- "Apply complete! Resources: 54 added, 0 changed, 0 destroyed"

Narration during fast-forward: "In about 17 minutes Terraform creates the VPC, subnets, IAM roles, KMS keys, EKS cluster, node group, ECR repositories, GuardDuty detector, and CloudWatch alarms."

#### 3c. Connect kubectl (~30s)

```bash
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev
kubectl get nodes -o wide
```

Point out: "Two Ready nodes, both private IPs only — no public IPs. That's exactly what we want."

#### 3d. Apply Kubernetes manifests (~1 min)

```bash
kubectl apply -f kubernetes/namespaces/
kubectl apply -f kubernetes/rbac/
kubectl apply -f kubernetes/deployments/
kubectl apply -f kubernetes/services/
kubectl apply -f kubernetes/ingress/
kubectl apply -f kubernetes/network-policies/

kubectl get pods -n fintech-app
```

Point out: "Pods scheduled, network policies active, ingress provisioning the ALB."

### Section 4 — Security Configurations (5:45–9:45)

**One command per layer. Narrate the security reasoning.**

#### 4a. IAM least privilege (Phase 4)

```bash
aws iam list-attached-role-policies --role-name fintech-secure-dev-eks-node-role
```

"Three policies only — worker, CNI, ECR-read. No S3, no EC2-full, no IAM-full."

#### 4b. Kubernetes RBAC (Phase 4)

```bash
kubectl get clusterrolebindings | grep -E "admin|developer|viewer"
kubectl describe clusterrole developer-role | head -20
```

"Developer role grants CRUD on workload resources but nothing on nodes or RBAC objects themselves."

#### 4c. Network Policies (Phase 5)

```bash
kubectl get networkpolicy -n fintech-app
```

"Default-deny on ingress AND egress. We then explicitly allow frontend → backend → db."

#### 4d. Data Encryption (Phase 6)

```bash
aws eks describe-cluster --name fintech-secure-dev \
  --query 'cluster.encryptionConfig'
```

"EKS secrets encrypted with our customer-managed KMS key. Same key encrypts EBS, ECR, Secrets Manager."

#### 4e. Container Security (Phase 7)

```bash
kubectl get pod -n fintech-app -l app=backend \
  -o jsonpath='{.items[0].spec.containers[0].securityContext}' | jq
```

Show:
```json
{
  "allowPrivilegeEscalation": false,
  "capabilities": {"drop": ["ALL"]},
  "readOnlyRootFilesystem": true,
  "runAsNonRoot": true,
  "runAsUser": 1000
}
```

"Every container: non-root, read-only root filesystem, no privilege escalation, zero capabilities."

ECR scanning:

```bash
aws ecr describe-image-scan-findings \
  --repository-name fintech-secure/backend \
  --image-id imageTag=latest \
  --query 'imageScanFindings.findingSeverityCounts'
```

"Scan-on-push plus Inspector continuous scanning. Zero critical CVEs."

#### 4f. Monitoring (Phase 8)

```bash
aws guardduty list-detectors
aws cloudwatch describe-alarms --alarm-name-prefix fintech-secure-dev \
  --query 'MetricAlarms[].{Name:AlarmName,State:StateValue}'
```

"GuardDuty active with EKS audit-log monitoring. Three alarms armed: failed auth, node CPU, and any new GuardDuty finding."

### Section 5 — Threat Simulation (9:45–13:15)

Two live demos. Capture both denials on camera.

#### 5a. Unauthorized Access (RBAC denial) — 90s

```bash
# Switch to viewer role
VIEWER_ROLE=$(cd terraform && terraform output -raw viewer_role_arn)
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev \
  --role-arn $VIEWER_ROLE --alias viewer

kubectl --context viewer delete deployment backend -n fintech-app
```

Expected output (show on screen):
```
Error from server (Forbidden): deployments.apps "backend" is forbidden:
  User "viewer" cannot delete resource "deployments" in API group "apps"
  in the namespace "fintech-app"
```

Narration: "Viewer has no delete permission. RBAC blocks it synchronously before the API server even considers the request."

Show the audit log:
```bash
aws logs tail /aws/eks/fintech-secure-dev/cluster --since 2m \
  | grep -i forbidden | head -3
```

"The denial is captured in the audit log with the exact user and verb."

#### 5b. Privilege Escalation (PSS denial) — 90s

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: escape-attempt
  namespace: fintech-app
spec:
  hostPID: true
  hostNetwork: true
  containers:
    - name: evil
      image: nginx
      securityContext:
        privileged: true
        runAsUser: 0
        capabilities:
          add: [SYS_ADMIN]
EOF
```

Expected output:
```
Error from server (Forbidden): pods "escape-attempt" is forbidden: violates PodSecurity "restricted:latest":
  host namespaces (hostNetwork=true, hostPID=true),
  privileged (container "evil" must not set securityContext.privileged=true),
  allowPrivilegeEscalation != false,
  unrestricted capabilities (SYS_ADMIN),
  runAsNonRoot != true,
  seccompProfile (must set RuntimeDefault or Localhost)
```

Narration: "Pod Security Standards block the entire class of container-escape pods at admission. The pod is never created. Defense in depth means every threat is caught by the right layer."

### Section 6 — Wrap-up (13:15–14:15)

On-screen: phase status table from the README.

Talking points:
- Nine phases, every one with real artifacts — Terraform, Kubernetes manifests, CI/CD, documentation
- Three attack scenarios all blocked or detected
- Full stack deployable and destroyable in 20 minutes

Cost callout:
```bash
cd terraform && terraform destroy -auto-approve
```

"And because this costs around seven dollars a day, we tear down between demos. Thanks for watching."

---

## Presentation (Separate from Video)

If you also need to present slides live in class, see:
- `docs/presentation-slides.md` — slide content ready to paste into Google Slides
- `docs/presentation-notes.md` — speaker notes matched to each slide
