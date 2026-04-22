# Phase 7: Container Security

## Overview

Phase 7 implements container-level security across the entire image lifecycle — from base image selection through build, scanning, and runtime.

| Layer | Control | Where |
|-------|---------|-------|
| Base image | Minimal, trusted images | `backend/Dockerfile`, `frontend/Dockerfile` |
| User context | Non-root user in image and pod | Dockerfiles + `securityContext` |
| Registry | ECR with KMS encryption + immutable tags | `terraform/modules/container-security` |
| Scanning (push) | `scan_on_push = true` | ECR config |
| Scanning (continuous) | ECR Enhanced Scanning via Inspector | `aws_ecr_registry_scanning_configuration` |
| Scanning (CI) | Trivy filesystem + image + config scans | `.github/workflows/trivy-scan.yml` |
| Runtime | Pod Security Standards (restricted) | `kubernetes/namespaces/namespaces.yaml` |
| Runtime | Fine-grained `securityContext` | Every `Deployment` / `StatefulSet` |

## 1. Dockerfile Hardening

### Backend (`backend/Dockerfile`)

- Multi-stage build → production image has no build toolchain
- `python:3.12-slim` base (~120MB, no shell tools beyond what Python needs)
- Dedicated `appuser` (UID 1000) with `/sbin/nologin`
- `--no-cache-dir` pip installs, no pip cache in final layer
- Runs as `appuser`; ports above 1024

### Frontend (`frontend/Dockerfile`)

- Multi-stage: builder strips `node_modules` from final image
- Final stage uses `nginxinc/nginx-unprivileged` — runs as UID 101 with nginx listening on 8080
- No root required at runtime (standard nginx image requires root to bind to port 80)

## 2. Amazon ECR with Scanning

Terraform module `container-security` provisions:

- Two repositories: `fintech-secure/frontend` and `fintech-secure/backend`
- **`image_tag_mutability = IMMUTABLE`** — deployed tags cannot be overwritten
- **KMS encryption** at rest using the same customer-managed key as Phase 6
- **`scan_on_push = true`** — every pushed image scanned for CVEs
- **Enhanced Scanning** — Amazon Inspector continuously re-scans images as new CVEs are published
- **Lifecycle policy** — untagged images expire after 1 day; only the 10 newest tags retained

Relevant resource:

```hcl
resource "aws_ecr_registry_scanning_configuration" "enhanced" {
  scan_type = "ENHANCED"
  rule {
    scan_frequency = "CONTINUOUS_SCAN"
    repository_filter {
      filter      = "${var.project_name}/*"
      filter_type = "WILDCARD"
    }
  }
}
```

## 3. CI/CD Scanning with Trivy

Two GitHub Actions workflows under `.github/workflows/`:

### `trivy-scan.yml` (runs on every PR)

| Job | What It Scans | Failure Condition |
|-----|---------------|-------------------|
| `trivy-fs-scan` | Source tree (deps, lockfiles) | HIGH/CRITICAL unfixed CVEs |
| `trivy-image-scan` | Built frontend + backend images | HIGH/CRITICAL unfixed CVEs |
| `kubernetes-manifest-scan` | All YAML under `kubernetes/` | HIGH/CRITICAL misconfigurations |

Findings are uploaded as SARIF to GitHub Code Scanning for visibility in PRs.

### `build-and-push.yml` (runs on `main` / tags)

1. Authenticates to AWS via OIDC (no static keys)
2. Builds frontend + backend images
3. **Runs a CRITICAL-severity Trivy gate** — pipeline fails if any critical CVE is present
4. Only then pushes to ECR

## 4. Pod Security Standards

The `fintech-app` namespace enforces the **restricted** Pod Security Standard (see `kubernetes/namespaces/namespaces.yaml`):

```yaml
labels:
  pod-security.kubernetes.io/enforce: restricted
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted
```

This blocks at admission:
- Privileged pods
- Host namespace sharing (PID, IPC, network)
- Privilege escalation
- Running as root without an explicit `runAsNonRoot: true`
- Adding Linux capabilities beyond the default set
- `hostPath` volumes

## 5. Runtime `securityContext`

Every application pod sets:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: <non-root UID>
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
```

This is applied in:
- `kubernetes/deployments/backend.yaml` (UID 1000)
- `kubernetes/deployments/frontend.yaml` (UID 101)
- `kubernetes/deployments/postgres.yaml` (UID 999)

Writable paths are provided via `emptyDir` volumes, keeping the container's root filesystem read-only.

## Verification

```bash
# 1. Confirm ECR scan-on-push enabled
aws ecr describe-repositories --repository-names fintech-secure/backend \
  --query 'repositories[0].imageScanningConfiguration'

# 2. Inspect scan results for the latest image
aws ecr describe-image-scan-findings \
  --repository-name fintech-secure/backend \
  --image-id imageTag=latest

# 3. Confirm enhanced scanning
aws ecr get-registry-scanning-configuration

# 4. Confirm namespace PSS
kubectl get namespace fintech-app -o jsonpath='{.metadata.labels}' | jq

# 5. Confirm pods are running non-root
kubectl get pod -n fintech-app -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].securityContext}{"\n"}{end}'

# 6. Try to create a privileged pod — should be REJECTED by PSS
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: privileged-test
  namespace: fintech-app
spec:
  containers:
    - name: bad
      image: nginx
      securityContext:
        privileged: true
EOF
# Expected: Error from server (Forbidden): pods "privileged-test" is forbidden:
#   violates PodSecurity "restricted:latest"
```

## Security Justification

| Threat | Control |
|--------|---------|
| Image tampering post-push | `IMMUTABLE` tag policy |
| Vulnerable dependencies | Trivy in CI + ECR scan-on-push + Inspector continuous scan |
| Container breakout via root | Non-root user in image; PSS blocks privileged pods |
| Writable filesystem abuse | `readOnlyRootFilesystem: true` |
| Privilege escalation | `allowPrivilegeEscalation: false` + drop ALL capabilities |
| Data theft from registry | KMS encryption at rest |
