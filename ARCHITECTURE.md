# Amazon EKS Security Immersion Day — Architecture, Flow & Documentation

A complete, beginner-friendly, **hands-on-verified** walkthrough of Amazon EKS security,
built on a real **EKS Auto Mode** cluster (`eks-auto`, Kubernetes 1.36) provisioned with
Terraform. Every command was executed against the live cluster and its **real output**
recorded.

> **Account/region used:** `us-west-2`. Secrets, tokens, and full account IDs are
> redacted/masked throughout so this repo is safe to publish.

---

## 1. Repository layout

```
terraform/
├── main.tf                     # Primary EKS Auto Mode cluster (eks-auto) + VPC
├── eks-auto-2/                 # 2nd Auto Mode cluster for VPC Lattice labs
├── eks-private-cluster/        # Fully-private Auto Mode cluster (no IGW/NAT, VPC endpoints)
├── kube-bench/                 # Temporary AL2023 node group for CIS benchmark labs
├── devsecops/                  # Inspector + CodePipeline container-security pipeline
│
├── ARCHITECTURE.md             # << THIS FILE — start here
├── command-log/                # Every command we ran, explained for beginners
│   ├── README.md               #   index of all 23 commands + concept-doc links
│   └── commands/               #   01..23 — one detailed file per command
├── modules-docs/               # Concept deep-dives (the "why" behind the commands)
└── workshop-tools/             # Reference for the CLI tools in the workshop IDE
```

- **`command-log/`** — the *what we did*: each numbered file has a **Quick Summary**
  (purpose / Kubernetes effect / AWS service used), a line-by-line breakdown, the **real
  executed output**, and beginner notes.
- **`modules-docs/`** — the *why*: conceptual explanations, diagrams-in-text, and security
  best practices for each module.

---

## 2. The big picture — three questions EKS security answers

Every module maps to one of three orthogonal questions:

```
   ┌─────────────────────────────────────────────────────────────────────┐
   │  WHO can reach the cluster?     (authentication + coarse authz)       │
   │     • IAM principals via aws-auth ConfigMap (legacy)   [cmd 05,10,12] │
   │     • IAM principals via EKS access entries (modern)   [cmd 18,19,21] │
   │     • Human users via an external OIDC IdP (Cognito)   [OIDC doc]     │
   ├─────────────────────────────────────────────────────────────────────┤
   │  WHAT can they do inside Kubernetes?   (fine-grained authz)           │
   │     • Kubernetes RBAC: Roles/Bindings, namespaces      [cmd 09,11]    │
   │     • EKS access policies (cluster-admin/admin/edit/view + scope)     │
   ├─────────────────────────────────────────────────────────────────────┤
   │  WHAT AWS can the workloads reach?   (pod → AWS identity)             │
   │     • IRSA (OIDC federation)                           [cmd 13–15]    │
   │     • EKS Pod Identity (associations + session tags)   [cmd 16,17,20] │
   ├─────────────────────────────────────────────────────────────────────┤
   │  WHAT may a pod BE?   (workload hardening at admission)               │
   │     • Pod Security Standards + Admission (PSA)          [cmd 23]       │
   │     • OPA/Gatekeeper custom admission policies          [cmd 24]      │
   ├─────────────────────────────────────────────────────────────────────┤
   │  HOW is traffic & the supply chain secured?                           │
   │     • Network Policies (L3/L4 eBPF)                     [cmd 25]      │
   │     • VPC Lattice (L7 cross-VPC) + mTLS with ALB        [concept]     │
   │     • Secrets Manager CSI (mount secrets)              [cmd 26]      │
   │     • Image Security: ECR controls / Inspector / signing [cmd 27]    │
   ├─────────────────────────────────────────────────────────────────────┤
   │  HOW do we detect & prove compliance?  (detective/audit)             │
   │     • GuardDuty + EKS audit logs + Log Insights         [cmd 28]      │
   │     • CIS Benchmark with kube-bench                     [concept]     │
   └─────────────────────────────────────────────────────────────────────┘
```

---

## 3. Module flow (the order we did it, and how it connects)

### Part 1 — Human/identity access to the cluster
| # | Module | Doc |
|---|--------|-----|
| 01–04 | Orientation + how EKS auth works (decode the STS token) | `iam-and-eks-access.md` |
| 05,10,11,12 | **Legacy `aws-auth`**: map IAM roles→K8s users, RBAC, test 3 personas | `iam-groups-and-roles-aws-auth.md`, `kubernetes-authentication-rbac.md`, `iam-rbac-module-conclusion.md` |
| 06–09 | Build the IAM roles/groups/users + K8s namespaces/RBAC behind those tests | (same) |
| 18,19,21 | **Modern access entries**: policies, auth modes, 3 personas scoped to `team-a` | `eks-access-management-controls.md`, `access-entries-persona-plan.md` |
| (concept) | **OIDC IdP**: authenticate human users via Cognito/Okta | `oidc-identity-provider-authentication.md` |

### Part 2 — Workload (pod) access to AWS
| # | Module | Doc |
|---|--------|-----|
| 13,14 | The problem: a pod has no AWS identity (`NoCredentials`) + the projected SA token | `irsa.md` |
| 15 | **IRSA**: OIDC provider → ServiceAccount+role → working S3 access | `irsa.md`, `irsa-complete-flow.md` |
| 16,17 | **EKS Pod Identity**: association → working S3 (simpler than IRSA) | `eks-pod-identity.md` |
| 20 | Pod Identity **ABAC**: session-tag conditions (cluster/namespace/object) | `eks-pod-identity.md` |

### Part 3 — Workload hardening (admission)
| # | Module | Doc |
|---|--------|-----|
| 23 | **Pod Security Standards / Admission** (enforce/warn/audit) | `pod-security-pss-psa.md` |
| 24 | **OPA/Gatekeeper** custom admission policy (deny privileged) | `opa-gatekeeper.md` |

### Part 4 — Network & supply-chain security
| # | Module | Doc |
|---|--------|-----|
| 25 | **Network Policies** (deny-all → allow client-one; VPC CNI + eBPF) | `network-policies.md` |
| (concept) | **VPC Lattice** (L7 cross-VPC/cluster) + **mTLS with ALB** | `network-security-lattice-mtls.md` |
| 26 | **Secrets Manager CSI** (mount a secret via ASCP + IRSA) | `secrets-manager-csi.md` |
| 27 | **Image Security** — ECR controls live; Inspector/DevSecOps/signing concept | `image-security.md` |

### Part 5 — Detective controls & compliance
| # | Module | Doc |
|---|--------|-----|
| 28 | **Detective Controls** — GuardDuty (flagged), EKS audit + Log Insights (live), CloudTrail | `detective-controls.md` |
| (concept) | **Regulatory Compliance** — CIS Benchmark with kube-bench | `regulatory-compliance-kube-bench.md` |

---

## 4. The two "OIDC" — a clarification that trips everyone up

| "OIDC" | Used by | Direction | Where in this repo |
|--------|---------|-----------|--------------------|
| **Cluster OIDC issuer** | **IRSA** (pods → AWS) | K8s → AWS STS | cmd 14/15 (`iss=oidc.eks...`) |
| **OIDC identity provider** | **Human user auth** | External IdP → K8s API | OIDC doc, cmd 22 |

Same technology (OIDC/JWT), opposite problems. cmd 22 shows both live on `eks-auto`: the
IRSA issuer exists, but **no** user-auth IdP is associated.

---

## 5. End-to-end identity chains (verified)

**IAM principal → cluster (legacy aws-auth):**
```
IAM User → IAM Group (assume-role policy) → IAM Role → [aws-auth mapRoles] → K8s user
   → RoleBinding → Role → namespace-scoped permission     (proven in cmd 11)
```

**IAM principal → cluster (modern access entries):**
```
IAM Role → EKS access entry → associated EKS access policy + scope → K8s permission
   (k8sTeamADev = admin@team-a, k8sTeamATest = view@team-a)        (proven in cmd 21)
```

**Pod → AWS (IRSA):**
```
Pod uses ServiceAccount (role-arn annotation) → webhook injects AWS_WEB_IDENTITY_TOKEN_FILE
   → STS AssumeRoleWithWebIdentity (verified via cluster OIDC provider) → temp creds  (cmd 15)
```

**Pod → AWS (Pod Identity):**
```
Pod uses ServiceAccount ↔ EKS Pod Identity association → agent injects
   AWS_CONTAINER_CREDENTIALS_FULL_URI → STS AssumeRole (+TagSession) → temp creds       (cmd 16)
   + session tags (cluster/namespace/SA) enable ABAC on trust & resource policies       (cmd 20)
```

---

## 6. Security best practices captured throughout

- **Least privilege everywhere** — scope IAM trust policies to specific principals (not
  `:root`), scope access policies to namespaces, scope S3 to specific objects via tags.
- **Prefer modern mechanisms on new clusters** — EKS **access entries** over `aws-auth`;
  **Pod Identity** over IRSA (unless you need IRSA's portability).
- **Never store long-lived credentials** on the filesystem (the lab does for teaching; it
  flags this every time).
- **Avoid `:latest` image tags** — pin versions/digests (supply-chain risk).
- **Pod Security**: pair `enforce` with `warn`/`audit` so controller-created workloads
  surface violations; default-deny privileged.
- **Auditability** — control-plane audit logging is pre-enabled; STS/EKS calls
  (`AssumeRoleForPodIdentity`) are traceable in CloudTrail (cmd 20).
- **One-way changes flagged** — e.g. we deliberately did **not** switch auth mode to
  `API` (irreversible, breaks ConfigMap labs) — cmd 19.

---

## 7. How to read this repo (for a newcomer)

1. Start here (`ARCHITECTURE.md`) for the map.
2. Open `command-log/README.md` and read commands **01→23 in order** — each is
   self-contained and beginner-oriented.
3. When a command references a concept, jump to the matching file in `modules-docs/`.
4. `workshop-tools/README.md` explains the CLI tools (kubectl, eksctl, jq, k9s, …).

---

## 8. Verification status

All 28 commands were executed against the live `eks-auto` cluster (account in `us-west-2`)
and their **real output** is recorded in each log file — including the intended
**failures** (NoCredentials, Forbidden, AccessDenied, PSA rejection, Gatekeeper denial,
network-policy block) that prove each security control works. Concept-only modules (OIDC IdP
association, VPC Lattice, mTLS with ALB, DevSecOps pipeline, image signing, kube-bench) are
documented with the exact commands/flow, and read-only state of the cluster was verified
where applicable (cmd 22, 28).

### Domains covered
| Domain | Status |
|--------|--------|
| IAM & Access Control (aws-auth, RBAC, access entries, OIDC IdP) | ✅ cmd 01–22 |
| Identity for workloads (IRSA, Pod Identity, ABAC) | ✅ cmd 13–20 |
| Pod Security (PSS/PSA, OPA/Gatekeeper) | ✅ cmd 23–24 |
| Network Security (Network Policies live; Lattice + mTLS concept) | ✅ cmd 25 + concept |
| Secrets (Secrets Manager CSI) | ✅ cmd 26 |
| Image Security (ECR live; Inspector/DevSecOps/signing concept) | ✅ cmd 27 + concept |
| Detective Controls (Log Insights live; GuardDuty concept) | ✅ cmd 28 + concept |
| Regulatory Compliance (kube-bench) | ✅ concept |

### Flagged (NOT enabled — cost / account-level / blast radius)
These are documented with exact enablement commands but **intentionally not applied**;
enable only with explicit approval:
- **Amazon GuardDuty** + EKS Protection/Runtime Monitoring (account-level, cost) — verified off.
- **Amazon Inspector** / ECR **ENHANCED** registry scanning (account-level, cost) — verified BASIC.
- **DevSecOps pipeline** (`devsecops/` — CodePipeline/CodeBuild/Lambda/etc.).
- **VPC Lattice** (`eks-auto-2/`) and **mTLS with ALB** + **ACM Private CA** (significant cost).
- **kube-bench** classic AL2023 node group (`kube-bench/`) — extra EC2 cost.

> One reversible cluster change **was** made for the Network Policy module (cmd 25): the
> default NodeClass was set to `networkPolicy: DefaultDeny` and the VPC CNI network-policy
> controller was enabled. Revert with
> `kubectl patch nodeclass default -p '{"spec":{"networkPolicy":"DefaultAllow"}}'` and
> deleting the `amazon-vpc-cni` ConfigMap if a fully-open network posture is desired.
