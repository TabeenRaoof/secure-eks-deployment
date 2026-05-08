# Presenter notes — Technical report deck

These notes follow **`docs/technical-report.md`** in narrative order. Use them with a slide deck you build in PowerPoint or Google Slides (for example by copying headings and bullets from that report or from an exported outline). **`docs/architecture-diagram.png`** is the figure for the architecture slide.

**Suggested length:** about 15–18 minutes, plus Q&A.

---

## Slide 1 — Title (~0:30)

**Say:** Introduce the CS581 signature project: a secure, cloud-native fintech-style workload on **Amazon EKS**, grounded in the full technical report. Name the team and each person’s main contribution (Terraform, Kubernetes, app, documentation, demos).

**Show:** Title slide only; course name and date if your template allows.

**Handoff:** “The report’s executive summary frames the whole story—we’ll walk through it on the next slide.”

---

## Slide 2 — Executive Summary (~1:00)

**Say:** The deliverable is not a toy cluster—it is a **defense-in-depth** design across **seven** areas: network, identity, data, container, **runtime** (PSS, hardening), monitoring, and response. Everything important is **Infrastructure as Code** (Terraform + manifests) and **CI/CD** (GitHub Actions, Trivy). The report documents **three** threat simulations that prove the controls work together, not in isolation.

**Show:** Emphasize “seven domains” and “three simulations.”

**Handoff:** “Why this problem is worth solving—sensitive fintech data on shared cloud infrastructure.”

---

## Slide 3 — System Context & Goals (~0:45)

**Say:** Fintech data is a **high-value** target. The project assumes an organization that must use **EKS** but cannot accept default security. Goals: **least privilege**, **encryption** at rest and in transit, **auditability**, and a path to **incident response**—matching the report’s executive summary and Section 1.

**Show:** Three bullets map to compliance-minded stakeholders.

**Handoff:** “Here is how we structured the system in AWS.”

---

## Slide 4 — Architecture Overview (~1:30)

**Say:** Walk the **north-south** path: Internet → **ALB** (TLS termination) → **frontend** pods → **backend** → **PostgreSQL**. Stress that **worker nodes** and the **control plane data plane** live in **private** subnets; there are **no public node IPs**. NAT provides **outbound-only** egress for pulls and AWS API calls.

**Show:** If the diagram image is present, trace paths with the cursor. If the slide is the placeholder bullets, say you will drop in `architecture-diagram.png` from the report.

**Handoff:** “That picture collapses into three conceptual planes.”

---

## Slide 5 — Three Architectural Planes (~1:00)

**Say:** **Network plane** = VPC layout, subnets, NAT, Flow Logs. **Compute plane** = EKS managed nodes and every workload pod. **Security and observability plane** = IAM, IRSA, KMS, Secrets Manager, GuardDuty, CloudWatch, SNS—everything that answers “who did what” and “what broke.”

**Show:** Match each bullet to one color or section if your template supports it.

**Handoff:** “A handful of design decisions, summarized from the report’s table, drove the whole build.”

---

## Slide 6 — Key Design Decisions (~1:15)

**Say:** Pick 2–3 rows from the report’s decision table and **justify** them aloud—e.g. **private nodes** vs public, **customer-managed KMS** vs AWS-managed, **IRSA** vs broad instance profiles, **immutable tags** and **PSS restricted** vs softer defaults. This slide is where you show you understand **trade-offs**, not just buzzwords.

**Show:** Invite the audience to disagree: “We could have chosen X; we chose Y because…”

**Handoff:** “We mapped classical threats to controls using STRIDE.”

---

## Slide 7 — Threat Model (STRIDE) (~1:30)

**Say:** STRIDE is a **structured** way to argue coverage. Quickly walk **spoofing → RBAC/IAM**, **tampering → TLS + KMS**, **repudiation → logs**, **information disclosure → Secrets Manager**, **DoS → scaling and quotas**, **elevation → PSS + non-root**. Do not read every bullet; **hit three** and mention the rest are in the report.

**Show:** STRIDE letter + mapping.

**Handoff:** “Implementation starts with Terraform modules.”

---

## Slide 8 — Terraform — Six Modules (~1:00)

**Say:** The report splits infra into **six** Terraform modules—VPC, IAM, security (SGs/NACLs/KMS), EKS, container security (ECR), monitoring (GuardDuty, alarms, Container Insights). The **root** module also wires **Secrets Manager** and **backend IRSA**. One `terraform apply` reproduces the environment.

**Show:** Optional: flash repo path `terraform/modules/` if demoing from laptop.

**Handoff:** “On top of that, Kubernetes manifests define workloads and policy.”

---

## Slide 9 — Kubernetes Workloads (~1:15)

**Say:** **Namespaces** carry **Pod Security** labels (`restricted` for the app). **RBAC** and **aws-auth** connect IAM personas to Kubernetes groups. **Deployments** run the app; **StatefulSet** runs Postgres. **Ingress** sends `/api` to the backend and `/` to the frontend. **NetworkPolicies** implement **default deny** with explicit allow paths—this is called out in the report as egress being as important as ingress.

**Show:** Mention one manifest path, e.g. `kubernetes/network-policies/`, for credibility.

**Handoff:** “CI/CD closes the loop from commit to registry.”

---

## Slide 10 — CI/CD (~0:45)

**Say:** **Trivy** on pull requests gives early feedback; **OIDC** to AWS avoids long-lived keys on **main** builds. A **severity gate** stops broken images from shipping. This mirrors Section 2.3 of the report.

**Show:** Name `.github/workflows/` if asked.

**Handoff:** “The application itself is a real three-tier system.”

---

## Slide 11 — Application Stack (~0:45)

**Say:** **Flask** backend with JWT and DB access; **React** SPA; **PostgreSQL**. The backend can load secrets from **Secrets Manager** using **IRSA**—no secrets baked into images.

**Handoff:** “Security controls by phase—network first.”

---

## Slide 12 — Network Security (Phase 5) (~1:00)

**Say:** **Segmentation**, **security groups**, **NACLs**, **Flow Logs**, and **NetworkPolicies** stack together. Call out that **policies** constrain **east-west** traffic between frontend, backend, and database.

**Handoff:** “Identity is the next layer—AWS and Kubernetes together.”

---

## Slide 13 — Identity & Access (Phase 4) (~1:15)

**Say:** **Least privilege** at three levels: **AWS IAM** for humans and cluster infra, **IRSA** for the **one** backend service account that needs Secrets Manager, **Kubernetes RBAC** so viewers cannot delete workloads. **aws-auth** is **explicit**—no accidental cluster-admin for every user.

**Handoff:** “Data protection—at rest and in transit.”

---

## Slide 14 — Data Security (Phase 6) (~1:00)

**Say:** **KMS** anchors encryption for EKS secrets, EBS, ECR, Secrets Manager, SNS. **ALB** presents **TLS 1.3** with a modern policy and redirects HTTP. Application secrets come from **Secrets Manager**, not Git.

**Handoff:** “Containers and supply chain—build and runtime.”

---

## Slide 15 — Container Security (Phase 7) (~1:00)

**Say:** **Minimal** images, **non-root**, **multi-stage** builds. **ECR** uses **immutable** tags and **enhanced** scanning. At runtime, **PSS restricted** and **dropped capabilities** limit breakout and lateral movement.

**Handoff:** “Monitoring and response complete the story before demos.”

---

## Slide 16 — Monitoring & Incident Response (Phase 8) (~1:00)

**Say:** **Logs** from the control plane, VPC, and workloads feed **CloudWatch**. **GuardDuty** adds **threat detection** including EKS-aware signals. **Alarms** to **SNS** drive human response; the report ties this to a **runbook** in the threat-simulation doc.

**Handoff:** “Three exercises validated that this is not shelfware.”

---

## Slide 17 — Threat Simulation 1 (~0:45)

**Say:** A **low-privilege** identity tries a **destructive** `kubectl` action. **RBAC** returns **403**; the attempt is in the **audit log**; repeated failure can **alarm**.

**Handoff:** “Admission control is the second line.”

---

## Slide 18 — Threat Simulation 2 (~0:45)

**Say:** A manifest tries **privileged** and host namespaces. **Pod Security** blocks it at **admission** with a detailed violation—**no pod** is created.

**Handoff:** “The third scenario is about detection, not prevention.”

---

## Slide 19 — Threat Simulation 3 (~0:45)

**Say:** **Root** AWS credentials are used; **GuardDuty** raises a finding quickly; the **GuardDuty alarm** notifies via SNS. This shows **async** detection when synchronous controls are bypassed by misuse.

**Handoff:** “We can map all of this back to the course requirements.”

---

## Slide 20 — Requirements Coverage (~1:00)

**Say:** Walk the checklist at high speed: VPC, EKS, Terraform, multi-tier app, IAM/IRSA, RBAC, network controls, encryption, TLS, scanning, PSS, logging, GuardDuty, **multiple** threat simulations. Point to **evidence paths** in the repo as listed in the report’s evaluation table.

**Handoff:** “What we would do differently next time—lessons learned.”

---

## Slide 21 — Lessons Learned (~1:15)

**Say:** Pick **two** lessons and tell a **short story** from implementation (e.g. IRSA wiring, NetworkPolicy egress, alert fatigue without runbooks, cost of 24/7 clusters). The report lists eight; you cannot cover all—**depth beats listing**.

**Show:** Invite one question: “Which lesson resonates with your experience?”

**Handoff:** “References and where to read more.”

---

## Slide 22 — Appendix & References (~0:30)

**Say:** **`technical-report.md`** / **`.docx`** are the canonical narrative; **phase*-** docs are deep dives; **EKS best practices**, **PSS**, **CIS**, **NIST 800-190**, **OWASP K8s Top 10** ground the design in industry guidance.

**Show:** URLs or QR codes if your deck uses them.

**Handoff:** “Happy to take questions.”

---

## Demo tips (optional add-on)

- If live demo: `kubectl get pods`, Ingress hostname, **read-only** `kubectl get networkpolicy`—avoid showing live credentials.
- If video-only: short screen recording of a successful health check and one **denied** RBAC command.

---

## Slide deck

Build slides manually from **`docs/technical-report.md`** (or paste **`docs/architecture-diagram.png`** on the architecture slide). There is no automated generator in this repo.

Place **`architecture-diagram.png`** under **`docs/`** for the report and slide figures.
