# Phase 1: Architecture Design and Security Justification

## 1. Overview

This document describes the architecture for a secure, cloud-native fintech application deployed on Amazon Web Services (AWS) using Amazon Elastic Kubernetes Service (EKS). The system is designed to handle sensitive user data while maintaining resilience against common cloud and container threats.

Every design decision is grounded in the principle of **defense in depth** — multiple overlapping security controls ensure that the failure of any single layer does not compromise the system.

## 2. Architecture Summary

| Component              | Technology                          | Purpose                                      |
|------------------------|-------------------------------------|----------------------------------------------|
| Container Orchestration| Amazon EKS (Kubernetes 1.29)        | Manage microservices lifecycle                |
| Compute                | EC2 Managed Node Groups (t3.medium) | Run application containers                   |
| Networking             | VPC with public/private subnets     | Network isolation and traffic control         |
| Load Balancing         | Application Load Balancer (ALB)     | TLS termination and traffic routing           |
| Identity               | IAM + IRSA + Kubernetes RBAC        | Least-privilege access at every layer         |
| Secrets                | AWS Secrets Manager                 | Secure storage of credentials and API keys    |
| Encryption             | AWS KMS                             | Customer-managed keys for data at rest        |
| Container Registry     | Amazon ECR                          | Private, scanned container images             |
| Monitoring             | CloudWatch + GuardDuty              | Logging, metrics, and threat detection        |
| Web Protection         | AWS WAF (optional)                  | Layer 7 request filtering                     |

## 3. Network Architecture

### 3.1 VPC Design

- **CIDR Block**: `10.0.0.0/16` (65,536 available IP addresses)
- **Region**: `us-west-2` (configurable)
- **Availability Zones**: 3 (for high availability)

| Subnet Type | AZ 1 (us-west-2a)  | AZ 2 (us-west-2b)  | AZ 3 (us-west-2c)  |
|-------------|---------------------|---------------------|---------------------|
| Public      | 10.0.1.0/24         | 10.0.2.0/24         | 10.0.3.0/24         |
| Private     | 10.0.4.0/24         | 10.0.5.0/24         | 10.0.6.0/24         |

### 3.2 Security Justification — Network

**Why public/private subnet separation?**
Worker nodes and databases reside exclusively in private subnets with no public IP addresses. Only the Application Load Balancer sits in public subnets. This eliminates direct internet access to compute and data resources, reducing the attack surface to a single controlled entry point.

**Why 3 Availability Zones?**
EKS requires a minimum of 2 AZs. Using 3 provides genuine high availability — the cluster continues operating normally even if an entire AZ experiences an outage. For a fintech application handling financial data, this level of availability is essential.

**Why NAT Gateway instead of public IPs on nodes?**
Private subnet instances need outbound internet access (for pulling container images, OS updates, etc.) but should never be directly reachable from the internet. A NAT Gateway provides outbound-only connectivity, preventing inbound attacks while allowing necessary egress traffic.

**Why VPC Flow Logs?**
All network traffic (accepted and rejected) is logged to CloudWatch. This provides a forensic audit trail for incident investigation and can be used to detect anomalous traffic patterns such as data exfiltration or lateral movement.

### 3.3 Network Security Layers

The architecture implements three layers of network security:

1. **NACLs (Network Access Control Lists)**: Stateless, subnet-level firewall rules. Acts as the first line of defense, filtering traffic before it reaches any instance.
2. **Security Groups**: Stateful, instance-level firewall rules. Applied to the ALB, EKS nodes, and RDS instances with least-privilege port/protocol restrictions.
3. **Kubernetes Network Policies**: Pod-level traffic control within the cluster. Restricts which pods can communicate with each other (e.g., only the backend can reach the database).

This layered approach ensures that even if one layer is misconfigured, the other layers continue to enforce security boundaries.

## 4. EKS Cluster Architecture

### 4.1 Control Plane

The EKS control plane (API server, etcd, controllers) is fully managed by AWS across multiple AZs. This eliminates the operational burden of securing and patching the Kubernetes control plane.

**API Server Access**:
- Private endpoint: **Enabled** — allows kubectl access from within the VPC
- Public endpoint: **Restricted** — limited to specific CIDR blocks (team members' IPs) rather than open to the internet

**Control Plane Logging** (all sent to CloudWatch):
- `api` — API server requests
- `audit` — who did what, when (critical for security investigations)
- `authenticator` — IAM-to-Kubernetes authentication events
- `controllerManager` — controller operations
- `scheduler` — pod scheduling decisions

### 4.2 Worker Nodes

- **Type**: Managed Node Groups (AWS handles provisioning, patching, and draining)
- **Instance**: `t3.medium` (2 vCPU, 4 GiB RAM) — sufficient for demo workloads
- **Scaling**: Min 1, Desired 2, Max 4 nodes
- **Placement**: Private subnets only
- **AMI**: Amazon EKS-optimized Amazon Linux 2

### 4.3 Security Justification — EKS

**Why Managed Node Groups?**
AWS automatically applies security patches and handles node lifecycle. This reduces the risk of running unpatched nodes with known vulnerabilities.

**Why private subnet placement?**
Worker nodes have no public IP addresses and cannot be directly accessed from the internet. SSH access to nodes (if needed) must go through a bastion host or AWS Systems Manager Session Manager — both provide audit trails.

**Why enable all control plane logs?**
Audit logs are the single most important security artifact in Kubernetes. They record every API call — who made it, what they requested, and whether it was allowed. This is essential for detecting unauthorized access attempts and for incident response.

## 5. Identity and Access Management

### 5.1 IAM Roles (AWS Level)

| Role | Trust Policy | Attached Policies | Purpose |
|------|-------------|-------------------|---------|
| EKS Cluster Role | `eks.amazonaws.com` | `AmazonEKSClusterPolicy` | Allows EKS to manage AWS resources for the cluster |
| Node Group Role | `ec2.amazonaws.com` | `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, `AmazonEC2ContainerRegistryReadOnly` | Minimum permissions for nodes to join the cluster and pull images |
| App Workload Role | OIDC (scoped to service account) | Custom policy for Secrets Manager read | Per-pod permissions via IRSA |

### 5.2 IRSA (IAM Roles for Service Accounts)

IRSA is a mechanism that maps a Kubernetes service account to an AWS IAM role. This provides **pod-level IAM permissions** instead of node-level permissions.

**Security Justification:**
Without IRSA, every pod on a node inherits the node's IAM role. If any pod is compromised, the attacker gains access to everything the node can do (pull images, read secrets, etc.). With IRSA, each pod gets only the specific permissions it needs. A compromised frontend pod cannot access backend secrets because it has a different (or no) IAM role.

### 5.3 Kubernetes RBAC

Within the cluster, Kubernetes RBAC (Role-Based Access Control) restricts what users and service accounts can do:
- **ClusterRoles/Roles**: Define permitted actions (get, list, create, delete) on resources (pods, services, secrets)
- **ClusterRoleBindings/RoleBindings**: Assign roles to users or service accounts

This will be configured in Phase 4 by the team.

## 6. Data Security

### 6.1 Encryption at Rest

| Resource | Encryption Method |
|----------|------------------|
| EKS Secrets | AWS KMS (customer-managed key) |
| EBS Volumes | AWS-managed encryption (default) |
| RDS Database | AWS KMS encryption (when provisioned) |
| S3 Buckets | SSE-S3 or SSE-KMS |

**Why customer-managed KMS keys for EKS secrets?**
Default EKS secret storage (etcd) uses base64 encoding, which is not encryption. By configuring envelope encryption with a customer-managed KMS key, Kubernetes secrets are encrypted before being stored in etcd. The KMS key can also be audited (CloudTrail logs every key usage) and rotated.

### 6.2 Encryption in Transit

- **External**: TLS termination at the ALB (HTTPS only, HTTP redirected)
- **Internal**: Kubernetes service mesh or pod-to-pod TLS (configurable)
- **AWS API calls**: All AWS SDK calls use TLS by default

### 6.3 Secrets Management

Application secrets (database passwords, API keys) are stored in **AWS Secrets Manager**, not in Kubernetes Secrets or environment variables. Secrets Manager provides:
- Automatic rotation
- Fine-grained IAM access control
- Audit trail via CloudTrail
- Encryption at rest with KMS

Pods access secrets via IRSA — only the pods that need a specific secret have the IAM permissions to read it.

## 7. Container Security

### 7.1 Image Security
- All images stored in **Amazon ECR** (private registry)
- ECR image scanning enabled (detects known CVEs)
- Additional scanning with **Trivy** in CI/CD pipeline
- Use minimal base images (e.g., `alpine`, `distroless`) to reduce attack surface

### 7.2 Runtime Security
- Containers run as **non-root** users
- Read-only root filesystem where possible
- Pod Security Standards enforced (restricted profile)
- Resource limits set on all containers (prevent resource exhaustion attacks)

## 8. Monitoring and Threat Detection

| Tool | Purpose | What It Detects |
|------|---------|-----------------|
| CloudWatch Logs | Centralized logging | Application errors, access patterns |
| CloudWatch Metrics | Resource monitoring | CPU/memory spikes, scaling events |
| EKS Audit Logs | Kubernetes API auditing | Unauthorized API calls, privilege escalation |
| VPC Flow Logs | Network traffic logging | Unusual traffic patterns, data exfiltration |
| AWS GuardDuty | Threat detection | Compromised instances, cryptocurrency mining, unusual API calls |
| Prometheus + Grafana | Cluster metrics (optional) | Pod health, resource utilization dashboards |

## 9. Threat Model

| Threat | Mitigation | Detection |
|--------|------------|-----------|
| Unauthorized API access | Private endpoint + RBAC + IAM | Audit logs + GuardDuty |
| Container escape | Pod Security Standards + non-root + read-only FS | GuardDuty + audit logs |
| Network lateral movement | Network Policies + Security Groups + private subnets | VPC Flow Logs |
| Secret exposure | Secrets Manager + IRSA + KMS encryption | CloudTrail audit |
| Supply chain attack (malicious image) | ECR scanning + Trivy + minimal base images | ECR scan results |
| DDoS | ALB + AWS WAF + auto-scaling | CloudWatch alarms |
| Privilege escalation | Least-privilege IAM + RBAC + IRSA | Audit logs + GuardDuty |
| Data exfiltration | Encryption in transit + VPC Flow Logs + egress rules | VPC Flow Logs + GuardDuty |

## 10. Compliance Alignment

While this is a demo environment, the architecture aligns with:
- **Principle of Least Privilege**: Every role, policy, and network rule grants only the minimum required access
- **Defense in Depth**: Multiple overlapping security layers at network, identity, data, and runtime levels
- **Separation of Duties**: Different IAM roles for cluster management, node operation, and workload execution
- **Audit Trail**: Comprehensive logging at every layer for accountability and incident response
