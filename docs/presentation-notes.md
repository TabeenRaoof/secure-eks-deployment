# Speaker Notes — Presentation

These notes are **per slide** and match `docs/presentation-slides.md`. Each section includes:

- **Time**: how long to spend on the slide
- **Say**: talking points in plain language (not a script — don't read verbatim)
- **Show**: what to highlight on the slide or demo
- **Handoff**: transition to the next slide

**Target duration**: ~12 minutes + 3 minutes Q&A.

---

## Slide 1 — Title (0:30)

**Say**:
- Good afternoon / morning. Today we're presenting our CS581 Signature Project.
- The project is a full secure deployment of a cloud-native fintech application on AWS EKS.
- Introduce your team — who did what at a high level.

**Show**:
- Leave the title slide up while speaking.

**Handoff**: "Let's start with why this project matters."

---

## Slide 2 — The Problem (0:45)

**Say**:
- Fintech apps handle money and personal data. They're a high-value target for attackers.
- Cloud and container platforms add attack surface: pod escapes, credential leaks, supply-chain attacks.
- Default configs are not secure. You have to design security in from day one.
- Our job was to build something that a security-conscious startup could actually deploy.

**Show**: Point out the three bullet categories.

**Handoff**: "We tackled this with a single strategy: defense in depth."

---

## Slide 3 — Defense in Depth (1:00)

**Say**:
- Defense in depth means no single control is relied on. Each layer has its own independent check.
- Walk through the table row by row briefly — network, identity, data, container, runtime, monitoring, response.
- If one layer fails, the next one catches the attack.
- This is the philosophy behind everything you'll see today.

**Show**: Highlight the full row "Identity" since RBAC and IRSA will come up several times later.

**Handoff**: "Here's what it all looks like on AWS."

---

## Slide 4 — Architecture (1:30)

**Say**:
- VPC across three availability zones for high availability.
- Public subnets host the ALB and NAT gateways — anything that needs an internet-facing IP.
- Private subnets host the EKS worker nodes. **These nodes have no public IPs**. The control plane ENIs are also in private subnets.
- The ALB terminates TLS 1.3 using an ACM certificate, then forwards to pods.
- Pods get outbound internet via the NAT gateways when they need to reach AWS APIs — but nobody can reach the pods from outside.

**Show**: Point to private subnets, emphasize "no public IPs". Trace the request path: Internet → ALB → frontend pod → backend pod → PostgreSQL pod.

**Handoff**: "Under the hood, the stack looks like this."

---

## Slide 5 — Tech Stack (0:30)

**Say**:
- AWS services listed are what Terraform provisions.
- Everything is Infrastructure as Code — not a single click in the AWS console for the core setup.
- The app is a real multi-tier system: Flask backend, React frontend, PostgreSQL.
- CI/CD runs in GitHub Actions with OIDC federation, so no long-lived AWS keys live in GitHub secrets.

**Show**: Mention that the full repo is reproducible from a fresh AWS account.

**Handoff**: "Let's walk through each phase of what we built."

---

## Slide 6 — Phase 1 & 2 (0:45)

**Say**:
- Phase 1 was the architecture design doc and security justification.
- Phase 2 was Terraform — six modules covering VPC, IAM, security primitives, EKS, container security, and monitoring.
- Every resource is tagged with Project and Environment for cost tracking.
- One `terraform apply` gives you the full stack in about 17 minutes.

**Show**: If you have a screenshot of `terraform plan` output with "50 to add", show it here.

**Handoff**: "Into that cluster goes our application."

---

## Slide 7 — Phase 3 (0:45)

**Say**:
- Three tiers: frontend, backend, database.
- Each tier runs as a different non-root user — UID 101, 1000, 999.
- Frontend uses nginx-unprivileged image that listens on 8080 instead of 80, so it doesn't need root.
- Backend uses IRSA to pull secrets from AWS Secrets Manager — no hard-coded credentials.
- Every pod has resource limits, liveness and readiness probes, and writable filesystem paths mounted as emptyDir so the root filesystem itself is read-only.

**Show**: Pull up a real `kubectl get pods -n fintech-app` screenshot during the talk if you can.

**Handoff**: "Now, who gets to do what in this cluster? That's Phase 4."

---

## Slide 8 — Phase 4 IAM + RBAC (1:00)

**Say**:
- Three personas: platform admin, developer, viewer.
- Each is an AWS IAM role with only `eks:DescribeCluster` — **no other AWS permissions**. All authorization is delegated to Kubernetes RBAC.
- IAM roles map to Kubernetes groups via the `aws-auth` ConfigMap.
- Kubernetes RBAC then decides what each group can do: cluster-wide for admins, workload management for devs, read-only for viewers.
- IRSA is the star: the backend ServiceAccount is bound to an IAM role with a trust policy scoped to exactly one OIDC subject. Only that specific pod in that specific namespace can assume the role. No static keys.

**Show**: If you have a diagram of IAM → aws-auth → RBAC group, highlight it.

**Handoff**: "Identity controls who can talk to the API. Network security controls who can talk to whom on the wire."

---

## Slide 9 — Phase 5 Network Security (0:45)

**Say**:
- We apply a default-deny NetworkPolicy in the application namespace. Nothing can talk to anything until we allow it.
- Then we layer on three explicit allow rules: ALB to frontend, frontend to backend, backend to database.
- Backend also needs to reach AWS APIs over HTTPS — we allow that, but only on port 443.
- The database pod is **egress-denied**. A legitimate database has no reason to initiate outbound connections. If it does, something's wrong.

**Show**: Point to the "database: fully blocked" line — this is a common oversight.

**Handoff**: "Data at rest and in transit are the next layer."

---

## Slide 10 — Phase 6 Data Security (0:45)

**Say**:
- One customer-managed KMS key encrypts **everything**: EBS, EKS secrets, Secrets Manager, ECR images, and the SNS topic.
- Using a customer-managed key (vs AWS-managed) gives us control over key policy and rotation, and every decrypt shows up in CloudTrail.
- TLS 1.3 on the ALB via ACM. SSL redirect is enforced, so plain HTTP isn't even an option.
- Secrets live in AWS Secrets Manager. The backend pulls them at startup via IRSA. There are literally zero secrets in the manifests or container images.

**Show**: Emphasize "zero secrets in manifests" — this is a common failure mode.

**Handoff**: "Now for the container layer."

---

## Slide 11 — Phase 7 Container Security (1:15)

**Say**:
- Start at the build stage. Multi-stage Dockerfiles — the final image has no build tools, just the runtime.
- Minimal base images: `python:3.12-slim`, `nginxinc/nginx-unprivileged:alpine`.
- Registry is ECR with three hardening choices:
  - Immutable tags so `:latest` can't be swapped out underneath a running pod.
  - KMS encryption.
  - Scan-on-push, **plus** Amazon Inspector Enhanced Scanning which continuously re-scans as new CVEs are published.
- CI/CD: every PR runs Trivy against the source, the container images, and the Kubernetes manifests. A pipeline fails on any unfixed high or critical CVE. Before push to ECR, a final critical-severity gate runs.
- At runtime, the namespace enforces the `restricted` Pod Security Standard. This blocks privileged pods, host-namespace use, and capability additions at admission — before a single byte is scheduled.

**Show**: ECR scan finding counts or a Trivy pipeline run would be powerful here.

**Handoff**: "Prevention is great, but some things only show up at runtime. That's where monitoring comes in."

---

## Slide 12 — Phase 8 Monitoring (1:00)

**Say**:
- EKS control plane logs five streams to CloudWatch: api, audit, authenticator, controller-manager, scheduler. Audit is the most useful — every API call captured.
- Container Insights collects per-pod CPU, memory, disk, restart counts, and stdout/stderr.
- VPC Flow Logs capture packet metadata for network-level forensics.
- GuardDuty continuously analyzes EKS audit logs, VPC Flow Logs, DNS, and CloudTrail. It has built-in detectors for things like anonymous API requests, crypto-mining traffic, and root credential usage.
- Three CloudWatch alarms: failed auth attempts, node CPU exhaustion, and any new GuardDuty finding. All go to an SNS topic that emails the team.

**Show**: GuardDuty findings page or alarms dashboard is ideal here.

**Handoff**: "We built all of this — but does it actually work? We tested it with three attack simulations."

---

## Slide 13 — Threat Scenario 1 (1:00)

**Say**:
- First, we simulated a compromised viewer account trying a destructive action.
- We assumed the viewer IAM role, reconfigured kubectl, and ran `kubectl delete deployment backend`.
- The API server responded with 403 Forbidden. The viewer role grants only read permissions — delete is not allowed.
- The denial is captured in the EKS audit log with the exact user, the verb, the resource, and the timestamp.
- This is **synchronous** — the attack is blocked before the delete even reaches the admission layer.
- If an attacker tries this repeatedly, the failed-auth alarm fires.

**Show**: Read the denial message aloud — it's the direct evidence.

**Handoff**: "Scenario two is more aggressive — trying to escape the sandbox."

---

## Slide 14 — Threat Scenario 2 (1:00)

**Say**:
- A common container-escape recipe: create a pod with `privileged: true`, `hostPID`, `hostNetwork`, and the `SYS_ADMIN` capability. That combination gives you the host.
- We applied a manifest with all those settings.
- Kubernetes **admission controller** rejected it. The pod object was never created. Scheduling never happened. A runtime detection tool never had to fire.
- The rejection message enumerates every policy the pod violated — six separate violations in one response.
- This is the strongest kind of control: attacks that literally cannot succeed.

**Show**: Read a couple of the violation lines — they're very specific.

**Handoff**: "Scenario three is about misuse of admin privileges, which we can only detect, not prevent."

---

## Slide 15 — Threat Scenario 3 (0:45)

**Say**:
- This one was actually a real finding that came up during development, which is useful because it's not synthetic.
- An administrator used AWS root account credentials to make an API call.
- GuardDuty flagged it within minutes with a `Policy:IAMUser/RootCredentialUsage` finding.
- The CloudWatch alarm on new GuardDuty findings fired and SNS sent an email.
- The takeaway is that we also monitor for **administrative misuse** — not just external attackers.
- Mitigation: our three persona roles cover every legitimate use case, so root never needs to be used.

**Show**: The GuardDuty finding screenshot is very persuasive evidence.

**Handoff**: "Let's sum up what we delivered."

---

## Slide 16 — Results (0:30)

**Say**:
- Every deliverable in the spec was completed with real artifacts — not just documentation.
- The project is fully reproducible: a fresh AWS account, one `terraform apply`, and the stack is up.
- Three threat scenarios tested end to end with captured evidence.

**Show**: Highlight that every row says "Complete".

**Handoff**: "We learned a few things along the way."

---

## Slide 17 — Lessons Learned (1:00)

**Say**:
- Pick 3-4 of the bullets to elaborate on — don't read them all.
- Suggested focus:
  - **Defense in depth works** — no single control caught every attack in Phase 9
  - **Immutable tags + continuous scanning** — mutable tags plus human discipline is a bug waiting to happen
  - **Network policies must cover egress** — ingress-only is a common mistake that opens lateral movement paths
  - **Alerts without runbooks are noise** — the CloudWatch alarm is only useful if someone knows what to do when it fires

**Show**: The list is there for reference; you don't need to read every bullet.

**Handoff**: "That's our project. Happy to take questions."

---

## Slide 18 — Q&A (remaining time + 3 min)

**Say**:
- Open the floor for questions.
- If there's silence, offer a prompt: "Happy to go deeper on IRSA, network policies, or any of the threat scenarios."

**Likely questions and quick answers**:

| Question | Answer |
|----------|--------|
| "Why Terraform and not eksctl?" | Terraform handles the whole stack (VPC, KMS, ECR, GuardDuty) in one tool. `eksctl` only covers EKS. |
| "Why PostgreSQL StatefulSet instead of RDS?" | For the demo. In production we'd use RDS — the same KMS key and SG setup applies. StatefulSet kept the project self-contained. |
| "How much does this cost?" | ~$7/day running, ~$210/month. We tear down between sessions with `terraform destroy`. |
| "What if `aws-auth` gets misconfigured?" | We'd lose non-node access. The node role entry is always preserved in our manifest. Recovery is via the cluster creator's IAM identity, which always has access. |
| "Why restricted PSS instead of privileged for convenience?" | We never needed privileged. Every pod we designed fits under restricted, so we enforce the most restrictive tier that still works. |
| "How do you rotate secrets?" | Rotate in Secrets Manager; pods pick up new values on next restart (or immediately if using a refresh loop). KMS key also has rotation enabled. |
| "Is TLS end-to-end or only to the ALB?" | Only to the ALB in this demo. For production, we'd add TLS inside the cluster with cert-manager or a service mesh. |
| "What's next?" | Add cert-manager for in-cluster mTLS, move the DB to RDS with multi-AZ, add a WAF in front of the ALB, and automate the `aws-auth` edits with Terraform. |

---

## Presenter Tips

- **Speak to the slide, don't read it**. If you find yourself reading, look at the audience instead.
- **Timestamps are guidelines**. If you finish a slide in 30 seconds, move on — don't pad.
- **Practice twice before the real talk**. Time yourself. Most people come in 20% over on first rehearsal.
- **Demos go last in presentations, first in videos**. For a live talk, keep live demos to the end so a technical glitch doesn't derail the rest.
- **Have a backup**. Screenshots of the live commands are a good safety net if the cluster is down during the talk.
