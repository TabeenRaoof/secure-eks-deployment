# Presentation Slides — Secure EKS Deployment

**How to use this file**: Each `## Slide N` heading below is a separate slide. Copy the **Title** and **Bullets** into Google Slides (`File → Import slides` won't take Markdown, so manual paste is simplest). Recommended layout: "Title and Body" for most slides, "Section Header" for dividers.

**Target length**: 18 slides, ~12-minute talk.

---

## Slide 1 — Title

**Secure Cloud-Native Application Deployment on AWS EKS**

Design, Implementation, and Security Hardening of a Cloud-Native Fintech Application

- CS581 Signature Project
- Team: [Name 1], [Name 2], [Name 3]
- Spring 2026

---

## Slide 2 — The Problem

**Fintech on the Cloud = High-Value Target**

- Sensitive user + transaction data
- Heavy compliance and audit requirements
- Container platforms introduce new attack surfaces:
  - Pod escape, privilege escalation, lateral movement
  - Leaked credentials, misconfigured IAM
  - Supply-chain attacks on container images
- Defaults are not secure — we must design security in

---

## Slide 3 — Our Approach: Defense in Depth

**Seven Layers, Seven Independent Controls**

| Layer | Control |
|-------|---------|
| Network | VPC, SGs, NACLs, Flow Logs |
| Identity | IAM least privilege + RBAC + IRSA |
| Data | KMS at rest, TLS 1.3 in transit |
| Container | ECR scan-on-push, Trivy CI, immutable tags |
| Runtime | Pod Security Standards, non-root, read-only FS |
| Monitoring | CloudWatch + GuardDuty + CloudTrail |
| Response | Alarms → SNS → runbook |

---

## Slide 4 — Architecture

*(Insert architecture-diagram.png as full-slide image)*

Key components:
- 3-AZ VPC with public/private subnet split
- EKS cluster in private subnets — no public node IPs
- ALB ingress in public subnets with ACM TLS 1.3
- NAT gateway for outbound-only node traffic

---

## Slide 5 — Technology Stack

**Infrastructure as Code + Kubernetes-Native**

- **AWS**: EKS, EC2, VPC, IAM, KMS, ECR, Secrets Manager, GuardDuty, CloudWatch, SNS
- **IaC**: Terraform 1.5+ with six reusable modules
- **Orchestration**: Kubernetes 1.29, Helm, AWS Load Balancer Controller
- **Application**: Python/Flask backend, React/Vite frontend, PostgreSQL 16
- **CI/CD**: GitHub Actions, Trivy, OIDC federation
- **Monitoring**: CloudWatch Container Insights, GuardDuty, optional Prometheus/Grafana

---

## Slide 6 — Phase 1 & 2: Design + Infrastructure

**Everything provisioned by one `terraform apply`**

- 6 Terraform modules (VPC, IAM, Security, EKS, Container Security, Monitoring)
- ~50 AWS resources deployed in ~17 minutes
- Multi-AZ, encrypted-at-rest from day one
- VPC Flow Logs and EKS control-plane logs enabled on creation

*(Screenshot: `terraform plan` output or resource graph)*

---

## Slide 7 — Phase 3: Multi-Tier Application

**Real App, Real Security**

- **Frontend**: React SPA, nginx-unprivileged (UID 101), listens on 8080
- **Backend**: Flask + gunicorn, non-root UID 1000, reads secrets via IRSA
- **Database**: PostgreSQL 16 StatefulSet, non-root UID 999, encrypted gp3 EBS
- All three: read-only root FS, dropped capabilities, resource limits, liveness/readiness probes

*(Screenshot: `kubectl get pods -n fintech-app` showing 5 Running pods)*

---

## Slide 8 — Phase 4: IAM + Kubernetes RBAC

**Three Personas + Zero Shared Credentials**

- IAM roles: `platform-admin`, `developer`, `viewer` — each with **only** `eks:DescribeCluster`
- Kubernetes RBAC: 3 ClusterRoles + 3 Roles + 6 Bindings
- `aws-auth` ConfigMap maps IAM ARN → K8s group
- **IRSA** for backend pods — no static AWS keys anywhere in the cluster

*(Diagram: IAM Role → aws-auth → K8s Group → RoleBinding → Role)*

---

## Slide 9 — Phase 5: Network Security

**Zero-Trust Pod Networking**

- Default-deny ingress **and** egress in `fintech-app` namespace
- Explicit allow rules: `ALB → frontend → backend → postgres`
- Backend egress to AWS APIs on 443 only
- Database egress: **fully blocked** (DB should never initiate outbound)
- Security Groups: cluster SG, node SG; NACLs at subnet level

*(Diagram: network policy flow)*

---

## Slide 10 — Phase 6: Data Security

**Encryption Everywhere**

At rest:
- KMS customer-managed key
- Encrypts EBS, EKS secrets, Secrets Manager bundle, ECR images, SNS
- Key rotation enabled

In transit:
- ALB serves TLS 1.3 via ACM (`ELBSecurityPolicy-TLS13-1-2-2021-06`)
- HTTP → HTTPS redirect enforced
- In-cluster kubelet/API TLS default

Secrets:
- Stored in AWS Secrets Manager
- Backend pulls via IRSA on startup — **no secrets in manifests or images**

---

## Slide 11 — Phase 7: Container Security

**Secure Supply Chain + Hardened Runtime**

- **Build**: multi-stage Dockerfiles, minimal bases, non-root users
- **Registry**: ECR with `IMMUTABLE` tags, KMS encryption, scan-on-push, **Amazon Inspector Enhanced Scanning**
- **CI/CD**: Trivy scans source, images, and K8s manifests on every PR; CRITICAL gate before push
- **Runtime**: Pod Security Standard `restricted` at namespace + explicit `securityContext` on every pod

*(Screenshot: ECR scan findings page or Trivy pipeline run)*

---

## Slide 12 — Phase 8: Monitoring & Logging

**See Everything, Alert on What Matters**

- EKS control-plane logs (api, audit, authenticator, ctrl-mgr, scheduler) → CloudWatch
- CloudWatch Container Insights → per-pod CPU/memory/restarts
- VPC Flow Logs → network-level forensics
- **GuardDuty** with EKS audit-log monitoring + EBS malware scanning
- **CloudWatch Alarms** (failed auth, node CPU, new GuardDuty finding) → SNS → email

*(Screenshot: CloudWatch alarms dashboard or GuardDuty findings page)*

---

## Slide 13 — Phase 9: Threat Simulation (1 of 3)

**Scenario 1 — Unauthorized Access Attempt**

- Attack: compromised `viewer` role tries `kubectl delete deployment backend`
- Detection: Kubernetes RBAC blocks with 403 Forbidden
- Mitigation: Least-privilege ClusterRole grants only read verbs
- Evidence: Denial captured in EKS audit log

```
Error: deployments.apps "backend" is forbidden: User "viewer" cannot
delete resource "deployments" in API group "apps" in "fintech-app"
```

---

## Slide 14 — Phase 9: Threat Simulation (2 of 3)

**Scenario 2 — Privilege Escalation Attempt**

- Attack: manifest tries to create privileged pod with `hostPID`, `hostNetwork`, `SYS_ADMIN`
- Detection: Pod Security Standards block at admission — pod never created
- Mitigation: `restricted` PSS profile enforced at namespace level
- Evidence: Enumerated policy violations in the rejection message

```
violates PodSecurity "restricted:latest":
  host namespaces (hostNetwork=true, hostPID=true),
  privileged, allowPrivilegeEscalation != false,
  unrestricted capabilities (SYS_ADMIN), ...
```

---

## Slide 15 — Phase 9: Threat Simulation (3 of 3)

**Scenario 3 — Root Credential Usage (GuardDuty)**

- Attack: AWS root account used for API calls
- Detection: GuardDuty raises `Policy:IAMUser/RootCredentialUsage` finding
- Alerting: CloudWatch alarm fires → SNS → email
- Mitigation: Three persona IAM roles exist so root is never required
- Lesson: Alerts on administrative anti-patterns are as important as alerts on external threats

*(Screenshot: GuardDuty finding page)*

---

## Slide 16 — Results

| Deliverable | Status |
|-------------|--------|
| VPC + EKS via Terraform | Complete |
| Multi-tier app deployed | Complete |
| IAM + RBAC + IRSA | Complete |
| Network + data security | Complete |
| Container security (ECR + Trivy + PSS) | Complete |
| Monitoring (GuardDuty + CloudWatch) | Complete |
| 3 threat scenarios validated | Complete |
| 15-page technical report | Complete |

**Every control was tested and verified end to end.**

---

## Slide 17 — Lessons Learned

1. **Defense in depth works** — no single control caught every attack
2. **IRSA is non-negotiable** for AWS access from pods
3. **Immutable tags + continuous scanning** beats human tag discipline
4. **Pod Security Standards** are better than PSP or custom webhooks
5. **Terraform modules over flat config** — 6 modules made each phase reviewable
6. **Network policies must cover ingress AND egress** — easy to miss
7. **Alerting is only as good as the runbook behind it**

---

## Slide 18 — Q&A / Thank You

**Questions?**

- Repository: `github.com/tabeenraoof/secure-eks-deployment`
- Technical report: `docs/technical-report.md`
- Demo video: *(link)*

*(Architecture diagram as background image)*
