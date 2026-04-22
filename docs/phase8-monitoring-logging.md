# Phase 8: Monitoring & Logging

## Overview

Phase 8 provides centralized observability and threat detection across three layers:

| Layer | Tool | Where Configured |
|-------|------|------------------|
| AWS control plane | CloudTrail (account-level) | AWS default |
| EKS control plane | CloudWatch Logs (API, audit, authenticator, controllerManager, scheduler) | `terraform/modules/eks/main.tf` |
| Node & container | CloudWatch Container Insights (EKS add-on) | `terraform/modules/monitoring/main.tf` |
| Network | VPC Flow Logs → CloudWatch | `terraform/modules/vpc/main.tf` |
| Threat detection | Amazon GuardDuty (with EKS audit-log + runtime monitoring) | `terraform/modules/monitoring/main.tf` |
| Alerting | CloudWatch alarms → SNS → email | `terraform/modules/monitoring/main.tf` |
| Metrics dashboard (optional) | Prometheus + Grafana (Helm) | `kubernetes/monitoring/` |

## 1. EKS Control Plane Logging

All five control plane log types are enabled at the cluster level:

```hcl
enabled_cluster_log_types = [
  "api",
  "audit",
  "authenticator",
  "controllerManager",
  "scheduler"
]
```

Logs stream to `/aws/eks/fintech-secure-dev/cluster` with **30-day retention** (explicit `aws_cloudwatch_log_group` resource — prevents unbounded log retention cost).

The **audit** log is the most valuable: every API call to the Kubernetes API server is captured with the caller identity, verb, resource, and response code.

## 2. VPC Flow Logs

Enabled in Phase 2 — captures source/destination IP, port, protocol, bytes, and accept/reject for every packet traversing the VPC. Used to investigate unusual east-west or egress traffic.

## 3. CloudWatch Container Insights

Installed as the `amazon-cloudwatch-observability` EKS add-on. Collects:

- Per-pod CPU, memory, disk, network
- Container restarts and termination reasons
- Stdout/stderr from every container
- Node-level metrics

Surfaced via the CloudWatch Container Insights console with pre-built dashboards.

## 4. GuardDuty

Enabled with two protections relevant to EKS:

```hcl
datasources {
  kubernetes {
    audit_logs { enable = true }    # Detects suspicious API calls
  }
  malware_protection {
    scan_ec2_instance_with_findings {
      ebs_volumes { enable = true } # On-demand EBS volume scans
    }
  }
}
```

GuardDuty continuously analyzes:
- EKS audit logs (kubectl exec abuse, anonymous requests, privileged pod creation)
- VPC Flow Logs (crypto mining beacons, C2 traffic)
- DNS logs (data exfiltration via DNS)
- CloudTrail (IAM misuse, root credential usage)

## 5. CloudWatch Alarms

| Alarm | Trigger | Purpose |
|-------|---------|---------|
| `failed-auth` | >10 API 4xx responses in 5 min | Possible RBAC probing / brute force |
| `node-high-cpu` | >80% node CPU for 10 min | Node exhaustion / runaway pod / crypto miner |
| `guardduty-findings` | Any new finding | Immediate threat notification |

All alarms publish to an SNS topic (`fintech-secure-dev-alarms`), encrypted with the project KMS key. An email subscription can be configured via the `alarm_email` variable.

## 6. Prometheus + Grafana (Optional)

For in-cluster metrics with custom dashboards, install the kube-prometheus-stack Helm chart into the `monitoring` namespace:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --values kubernetes/monitoring/prometheus-values.yaml
```

See `kubernetes/monitoring/prometheus-values.yaml` for hardened values (non-root, resource limits, reduced retention).

## Verification

```bash
# 1. Confirm EKS control plane logs are enabled
aws eks describe-cluster --name fintech-secure-dev \
  --query 'cluster.logging.clusterLogging'

# 2. Tail recent audit log events
aws logs tail /aws/eks/fintech-secure-dev/cluster \
  --log-stream-name-prefix kube-apiserver-audit --since 10m

# 3. Confirm GuardDuty is enabled
aws guardduty list-detectors
aws guardduty get-detector --detector-id <ID> \
  --query '{Status:Status,Features:Features[*].Name,KubernetesAudit:DataSources.Kubernetes.AuditLogs.Status}'

# 4. List GuardDuty findings
aws guardduty list-findings --detector-id <ID>

# 5. Confirm Container Insights add-on
aws eks list-addons --cluster-name fintech-secure-dev
kubectl get pods -n amazon-cloudwatch

# 6. Confirm VPC Flow Logs
aws ec2 describe-flow-logs \
  --filter "Name=tag:Project,Values=fintech-secure"

# 7. List active alarms
aws cloudwatch describe-alarms \
  --alarm-name-prefix fintech-secure-dev
```

## Security Justification

| Requirement | Implementation |
|-------------|---------------|
| Audit trail | EKS audit log + CloudTrail capture every API call |
| Threat detection | GuardDuty with EKS runtime monitoring |
| Anomaly detection | CloudWatch alarms on failed auth, CPU, findings |
| Network visibility | VPC Flow Logs capture all traffic |
| Incident response | SNS alerts route to on-call email/Slack |
| Tamper resistance | Log groups encrypted with KMS, retention enforced via Terraform |
