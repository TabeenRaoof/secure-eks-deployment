# Phase 9: Threat Simulation & Mitigation

## Scenario 1: Unauthorized Access Attempt

### Attack
An attempt was made to access Kubernetes resources without proper permissions.

### Detection
The system denied access, and the event can be observed in logs (CloudWatch / Kubernetes logs).

### Mitigation
Role-Based Access Control (RBAC) was enforced to restrict access.

### Lesson Learned
Always apply least privilege to prevent unauthorized access.


## Scenario 2: Privilege Escalation Attempt

### Attack
A pod was configured to run with elevated privileges, which is a security risk.

### Detection
The issue was identified by reviewing the pod configuration and security settings.

### Mitigation
Privilege escalation was disabled, and the container was configured to run as a non-root user.

### Lesson Learned
Never allow privileged containers unless absolutely necessary.