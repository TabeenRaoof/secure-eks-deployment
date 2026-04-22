# Phase 4: Identity & Access Management

This document describes the IAM and Kubernetes RBAC configuration implemented for the fintech-secure EKS cluster.

## Overview

Phase 4 implements three layers of identity and access control:

| Layer | Mechanism | Where Defined |
|-------|-----------|---------------|
| AWS authentication | IAM roles assumed by team members | `terraform/modules/iam/main.tf` |
| IAM → K8s mapping | `aws-auth` ConfigMap | `kubernetes/rbac/aws-auth-configmap.yaml` |
| K8s authorization | RBAC Roles, ClusterRoles, Bindings | `kubernetes/rbac/` |
| Pod-level AWS access | IRSA (IAM Roles for Service Accounts) | `terraform/main.tf` + `kubernetes/rbac/service-accounts.yaml` |

## Architecture

```
IAM User/Role
    │
    ▼
┌──────────────────────────┐
│  aws-auth ConfigMap      │  ← maps IAM ARN → K8s username + groups
│  (kube-system)           │
└──────────────────────────┘
    │
    ▼
┌──────────────────────────┐
│  Kubernetes RBAC         │  ← ClusterRoleBindings / RoleBindings
│  (cluster + namespace)   │     check group membership
└──────────────────────────┘
    │
    ▼
  Allowed / Denied
```

## IAM Roles (Terraform)

Three IAM roles are created with no AWS policies beyond `eks:DescribeCluster` (needed for `aws eks update-kubeconfig`). All authorization is delegated to Kubernetes RBAC.

| IAM Role | K8s Group | Intended For |
|----------|-----------|-------------|
| `fintech-secure-platform-admin` | `platform-admins` | Ops lead, infrastructure management |
| `fintech-secure-developer` | `developers` | Team members deploying application code |
| `fintech-secure-viewer` | `viewers` | Auditors, read-only monitoring |

Each role's trust policy allows any IAM principal in the same AWS account to assume it. Restrict the `Principal` in production to specific IAM users or groups.

## Kubernetes RBAC

### ClusterRoles

| ClusterRole | Permissions |
|-------------|-------------|
| `cluster-admin-role` | Full access to all resources (equivalent to built-in `cluster-admin`) |
| `developer-role` | CRUD on workload resources (pods, deployments, services, configmaps, secrets, ingresses). No access to nodes, namespaces, or RBAC objects |
| `viewer-role` | Read-only access to workload and cluster resources |

### Namespace-Scoped Roles

| Role | Namespace | Permissions |
|------|-----------|-------------|
| `app-deployer` | `fintech-app` | CRUD on pods, deployments, services, configmaps, secrets, ingresses |
| `app-viewer` | `fintech-app` | Read-only on pods, deployments, services, events |
| `monitoring-operator` | `monitoring` | CRUD on monitoring-related resources (deployments, daemonsets, configmaps) |

### Bindings

| Binding | Type | Group → Role |
|---------|------|-------------|
| `cluster-admin-binding` | ClusterRoleBinding | `platform-admins` → `cluster-admin-role` |
| `developer-binding` | ClusterRoleBinding | `developers` → `developer-role` |
| `viewer-binding` | ClusterRoleBinding | `viewers` → `viewer-role` |
| `app-deployer-binding` | RoleBinding (fintech-app) | `developers` → `app-deployer` |
| `app-viewer-binding` | RoleBinding (fintech-app) | `viewers` → `app-viewer` |
| `monitoring-operator-binding` | RoleBinding (monitoring) | `platform-admins` → `monitoring-operator` |

## IRSA (IAM Roles for Service Accounts)

IRSA allows Kubernetes pods to assume an AWS IAM role without static credentials. The mechanism uses the EKS OIDC provider.

| Service Account | Namespace | IAM Role | AWS Permissions |
|----------------|-----------|----------|-----------------|
| `app-backend` | `fintech-app` | `fintech-secure-dev-app-workload-role` | `secretsmanager:GetSecretValue`, `kms:Decrypt` |
| `app-frontend` | `fintech-app` | *(none)* | No AWS access needed |

The backend pods can read application secrets from AWS Secrets Manager and decrypt them via KMS — all without embedding any AWS credentials.

## Namespace Isolation

| Namespace | Purpose | Pod Security Standard |
|-----------|---------|----------------------|
| `fintech-app` | Application workloads (frontend, backend, database) | `restricted` |
| `monitoring` | Observability tools (Prometheus, Grafana) | `baseline` |
| `kube-system` | Cluster system components (managed by EKS) | Default |

The `fintech-app` namespace enforces the `restricted` Pod Security Standard, which requires non-root containers, read-only root filesystems, and no privilege escalation.

## Deployment Steps

### 1. Apply Terraform Changes

```bash
cd terraform
terraform plan    # review the 3 new IAM roles + eks-access policy
terraform apply
```

### 2. Create Namespaces

```bash
kubectl apply -f kubernetes/namespaces/namespaces.yaml
```

### 3. Apply RBAC Manifests

```bash
kubectl apply -f kubernetes/rbac/cluster-roles.yaml
kubectl apply -f kubernetes/rbac/app-roles.yaml
kubectl apply -f kubernetes/rbac/role-bindings.yaml
kubectl apply -f kubernetes/rbac/service-accounts.yaml
```

### 4. Configure aws-auth ConfigMap

Edit `kubernetes/rbac/aws-auth-configmap.yaml` and replace `<ACCOUNT_ID>` with your AWS account ID:

```bash
# Get your account ID
aws sts get-caller-identity --query Account --output text

# Edit the file, then apply
kubectl apply -f kubernetes/rbac/aws-auth-configmap.yaml
```

> **Warning**: Be careful editing `aws-auth`. A misconfiguration can lock you out of the cluster. Always keep the node role mapping intact.

## Verification

### Verify RBAC roles exist

```bash
kubectl get clusterroles | grep fintech
kubectl get roles -n fintech-app
kubectl get roles -n monitoring
```

### Verify bindings

```bash
kubectl get clusterrolebindings | grep -E "admin-binding|developer-binding|viewer-binding"
kubectl get rolebindings -n fintech-app
kubectl get rolebindings -n monitoring
```

### Verify service accounts

```bash
kubectl get serviceaccounts -n fintech-app
```

### Test RBAC (as developer)

```bash
# Assume the developer role
aws sts assume-role --role-arn $(terraform output -raw developer_role_arn) --role-session-name dev-test

# Configure kubectl with the assumed role
aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev --role-arn $(terraform output -raw developer_role_arn)

# Should succeed (developer has pod access)
kubectl get pods -n fintech-app

# Should fail (developer cannot access RBAC objects)
kubectl get clusterroles
```

## Security Justification

| Principle | Implementation |
|-----------|---------------|
| **Least privilege** | Three tiered roles; no role has more access than needed |
| **Separation of duties** | Admins, developers, and viewers have distinct permissions |
| **Defense in depth** | AWS IAM authenticates, then K8s RBAC authorizes — two independent checks |
| **No shared credentials** | IRSA eliminates static AWS keys in pods |
| **Namespace isolation** | Workloads and monitoring are separated with independent RBAC |
| **Pod Security Standards** | `restricted` profile enforced on the application namespace |
