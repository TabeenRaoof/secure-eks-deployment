# Kubernetes Manifests — Phase 3+

This directory will contain all Kubernetes manifests for deploying the fintech application.

## Prerequisites

Before deploying anything here, ensure:
1. The EKS cluster is running (Phase 2 — see root README)
2. `kubectl` is configured: `aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev`
3. You can connect: `kubectl get nodes` shows nodes in `Ready` status

## Suggested Directory Structure

```
kubernetes/
├── namespaces/                # Namespace definitions
│   └── app-namespace.yaml
├── deployments/               # Application deployments
│   ├── frontend.yaml          # React/static frontend
│   ├── backend.yaml           # API server (Node.js or Python)
│   └── database.yaml          # PostgreSQL (if containerized)
├── services/                  # Service definitions
│   ├── frontend-svc.yaml      # ClusterIP or LoadBalancer
│   ├── backend-svc.yaml       # ClusterIP
│   └── database-svc.yaml      # ClusterIP (internal only)
├── ingress/                   # Ingress controller + rules
│   ├── nginx-ingress.yaml     # NGINX Ingress Controller
│   └── app-ingress.yaml       # Ingress routing rules
├── rbac/                      # RBAC policies (Phase 4)
│   ├── roles.yaml
│   └── rolebindings.yaml
├── network-policies/          # Network Policies (Phase 5)
│   ├── deny-all.yaml          # Default deny
│   ├── frontend-policy.yaml   # Allow frontend -> backend
│   └── backend-policy.yaml    # Allow backend -> database
├── secrets/                   # Secret references (Phase 6)
│   └── external-secrets.yaml  # AWS Secrets Manager integration
├── security/                  # Pod security (Phase 7)
│   └── pod-security.yaml      # Pod Security Standards
└── monitoring/                # Monitoring (Phase 8)
    └── prometheus-values.yaml # Prometheus/Grafana Helm values
```

## Application Requirements

The application should be a multi-tier fintech app with:

1. **Frontend**: Serves the UI, talks to the backend API
   - Expose via Ingress (HTTPS)
   - Run as non-root user
   - Read-only root filesystem

2. **Backend API**: Handles business logic and data access
   - ClusterIP service (internal only, accessed via Ingress)
   - Uses IRSA to access AWS Secrets Manager (role already configured in Terraform)
   - Service account: `app-backend` in `default` namespace

3. **Database**: PostgreSQL
   - Option A: Amazon RDS (preferred — managed, encrypted, backed up)
   - Option B: Containerized PostgreSQL (simpler but less production-ready)
   - ClusterIP service (internal only, no external access)

## Key Security Requirements

- All containers must run as **non-root** users
- Use **resource limits** on all pods (CPU and memory)
- Never store secrets in manifests — use AWS Secrets Manager + IRSA
- Apply **Network Policies** to restrict pod-to-pod traffic
- Use **Pod Security Standards** (restricted profile)

## Deployment Order

1. Namespaces
2. RBAC (Roles + RoleBindings)
3. Secrets/ConfigMaps
4. Database deployment + service
5. Backend deployment + service
6. Frontend deployment + service
7. Ingress controller + rules
8. Network policies
