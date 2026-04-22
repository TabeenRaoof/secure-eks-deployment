# Kubernetes Manifests

All manifests apply to the `fintech-app` and `monitoring` namespaces created in Phase 4.

## Directory Structure

```
kubernetes/
├── namespaces/          # Phase 4: fintech-app, monitoring (with PSS labels)
├── rbac/                # Phase 4: ClusterRoles, Roles, Bindings, aws-auth, ServiceAccounts
├── deployments/         # Phase 3: frontend, backend, postgres (StatefulSet)
├── services/            # Phase 3: ClusterIP services for all tiers
├── ingress/             # Phase 6: ALB ingress with ACM TLS
├── network-policies/    # Phase 5: default deny + tier-to-tier allow rules
└── monitoring/          # Phase 8: Prometheus/Grafana Helm values (optional)
```

## Prerequisites

1. EKS cluster provisioned (`terraform apply` — see root README)
2. `kubectl` configured: `aws eks update-kubeconfig --region us-west-2 --name fintech-secure-dev`
3. AWS Load Balancer Controller installed (required for the ALB Ingress):
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
     -n kube-system --set clusterName=fintech-secure-dev
   ```

## Deployment Order

Apply manifests in this exact order — each layer depends on the one before it:

```bash
# 1. Namespaces (with Pod Security Standard labels)
kubectl apply -f kubernetes/namespaces/

# 2. RBAC (roles, bindings, ServiceAccounts, aws-auth)
#    NOTE: Edit aws-auth-configmap.yaml first — replace <ACCOUNT_ID>
kubectl apply -f kubernetes/rbac/

# 3. Application workloads (requires ECR images to exist — see Phase 7)
kubectl apply -f kubernetes/deployments/postgres.yaml
kubectl apply -f kubernetes/deployments/backend.yaml
kubectl apply -f kubernetes/deployments/frontend.yaml

# 4. Services
kubectl apply -f kubernetes/services/

# 5. Ingress (requires ACM cert ARN in the manifest)
kubectl apply -f kubernetes/ingress/

# 6. Network Policies (apply LAST — they block traffic until rules exist)
kubectl apply -f kubernetes/network-policies/
```

## Key Security Requirements (All Enforced)

- All containers run as **non-root** (UIDs 101, 999, 1000)
- **Read-only root filesystem** on frontend and backend
- **`allowPrivilegeEscalation: false`** and **drop ALL capabilities** on every pod
- **Resource limits** set on every container
- **No secrets in manifests** — backend uses IRSA → AWS Secrets Manager
- **Network policies** default-deny with tier-to-tier allow rules
- **Pod Security Standards** enforced at the namespace level (`restricted`)

## Teardown

```bash
kubectl delete -f kubernetes/network-policies/
kubectl delete -f kubernetes/ingress/
kubectl delete -f kubernetes/services/
kubectl delete -f kubernetes/deployments/
kubectl delete -f kubernetes/rbac/
kubectl delete -f kubernetes/namespaces/
```
