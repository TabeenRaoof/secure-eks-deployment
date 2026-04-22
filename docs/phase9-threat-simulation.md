# Phase 9: Threat Simulation & Mitigation

## Overview

Three attack scenarios were simulated against the deployed cluster to validate the security controls from Phases 4–8. Each scenario documents the attack, the detection mechanism, the mitigation in place, and the lessons learned.

| Scenario | Threat Type | Mitigated By |
|----------|-------------|--------------|
| 1 | Unauthorized API access | Kubernetes RBAC + EKS audit logs |
| 2 | Privilege escalation via pod | Pod Security Standards + CloudWatch alarms |
| 3 | IAM misuse / root credential usage | GuardDuty threat detection |

---

## Scenario 1 — Unauthorized Access Attempt (RBAC Denial)

### Attack
An attacker (or a compromised viewer account) attempts to delete a production deployment.

```bash
# Assume the viewer IAM role
aws sts assume-role \
  --role-arn "$(terraform output -raw viewer_role_arn)" \
  --role-session-name attack-sim

# Re-auth kubectl as viewer
aws eks update-kubeconfig --region us-west-2 \
  --name fintech-secure-dev \
  --role-arn "$(terraform output -raw viewer_role_arn)"

# Try a destructive action
kubectl delete deployment backend -n fintech-app
```

### Detection
```
Error from server (Forbidden): deployments.apps "backend" is forbidden:
  User "viewer" cannot delete resource "deployments" in API group "apps"
  in the namespace "fintech-app"
```

The denial is logged in the EKS audit log:

```bash
aws logs filter-log-events \
  --log-group-name /aws/eks/fintech-secure-dev/cluster \
  --filter-pattern '{ $.user.username = "viewer" && $.responseStatus.code = 403 }' \
  --limit 5
```

### Mitigation
- **Kubernetes RBAC** — the `viewer-role` ClusterRole grants only `get/list/watch` verbs. No write permissions.
- **CloudWatch alarm `failed-auth`** — triggers if more than 10 such denials occur in a 5-minute window.

### Incident Response
1. Identify the IAM principal from the audit log `user.extra.arn` field.
2. Revoke the principal's AWS access (detach policies / delete access keys).
3. Remove the corresponding entry from the `aws-auth` ConfigMap.
4. Rotate any credentials associated with the compromised principal.

### Lesson Learned
Defense in depth works: the IAM role authenticates, RBAC authorizes, and both are independently audited. A compromised viewer role cannot escalate into a destructive action.

---

## Scenario 2 — Privilege Escalation Attempt (PSS Denial)

### Attack
A malicious or misconfigured manifest attempts to deploy a privileged pod with host-namespace access — a classic container-escape precursor.

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
        allowPrivilegeEscalation: true
        capabilities:
          add: [SYS_ADMIN]
EOF
```

### Detection
Kubernetes admission controller blocks it before the pod is ever scheduled:

```
Error from server (Forbidden): error when creating "STDIN":
  pods "escape-attempt" is forbidden: violates PodSecurity "restricted:latest":
    host namespaces (hostNetwork=true, hostPID=true),
    privileged (container "evil" must not set securityContext.privileged=true),
    allowPrivilegeEscalation != false (container "evil" must set securityContext.allowPrivilegeEscalation=false),
    unrestricted capabilities (container "evil" must not include "SYS_ADMIN" in securityContext.capabilities.add),
    runAsNonRoot != true, seccompProfile (pod or container "evil" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
```

### Mitigation
- **Pod Security Standards** — `fintech-app` namespace enforces the `restricted` profile, blocking the entire class of attacks at admission.
- **Pod `securityContext`** in all real Deployments:
  - `runAsNonRoot: true`, non-root UID
  - `readOnlyRootFilesystem: true`
  - `allowPrivilegeEscalation: false`
  - `capabilities.drop: [ALL]`
  - `seccompProfile.type: RuntimeDefault`

### Incident Response
1. Capture the denial event from the audit log.
2. Identify which IAM principal / CI pipeline attempted the action.
3. Review recent commits to the GitOps repo for malicious manifests.
4. If the attempt came via a compromised service account token, rotate the SA and investigate how the token was exfiltrated.

### Lesson Learned
PSS stops the entire class of privilege-escalation attacks at the admission layer — no runtime detection, no remediation, no incident. The attack literally cannot create a dangerous pod.

---

## Scenario 3 — IAM Misconfiguration (GuardDuty Detection)

### Attack
An administrator uses AWS root account credentials to make API calls — a common and dangerous misconfiguration.

```bash
# (Performed using root credentials on a test account)
aws ec2 describe-instances --region us-west-2
```

### Detection
GuardDuty raises a `Policy:IAMUser/RootCredentialUsage` finding within minutes:

```bash
aws guardduty list-findings \
  --detector-id "$(terraform output -raw guardduty_detector_id)" \
  --finding-criteria '{"Criterion":{"type":{"Eq":["Policy:IAMUser/RootCredentialUsage"]}}}'

aws guardduty get-findings \
  --detector-id "$DETECTOR" \
  --finding-ids "$FINDING_ID"
```

The `guardduty-findings` CloudWatch alarm fires and publishes to the alarms SNS topic, which delivers email notification.

### Mitigation
- **IAM least-privilege roles** (Phase 4) — three persona roles (admin, developer, viewer) cover all legitimate workflows; nobody needs root.
- **GuardDuty** continuous monitoring flags root usage immediately.
- **SNS → Email alert** ensures the team is paged on detection.

### Incident Response
1. Disable root access keys: `aws iam delete-access-key --user-name root --access-key-id <KEY>`
2. Enable/rotate root MFA.
3. Review CloudTrail for every action taken under root credentials.
4. If any action was unauthorized, follow credential-compromise playbook (rotate affected resources, revoke sessions).

### Lesson Learned
Alerts on administrative anti-patterns are as important as alerts on external threats. Root credential usage is almost always a misconfiguration or an attack in progress.

---

## Summary

| Scenario | Detection Time | Mitigation Layer | Result |
|----------|---------------|-----------------|--------|
| Unauthorized API access | Real-time (synchronous) | Kubernetes RBAC | **Blocked at authorization** |
| Privilege escalation | Real-time (synchronous) | Pod Security Standards | **Blocked at admission** |
| Root credential usage | ~5 minutes (async) | GuardDuty + SNS alarm | **Detected and alerted** |

All three scenarios demonstrate **defense in depth**: no single control is relied upon, and each attack is caught by a different layer.
