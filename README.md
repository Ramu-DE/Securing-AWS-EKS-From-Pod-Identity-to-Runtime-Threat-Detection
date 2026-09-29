# Securing AWS EKS — From Pod Identity to Runtime Threat Detection

A complete, **beginner-friendly and hands-on-verified** walkthrough of Amazon EKS security,
built on a real **EKS Auto Mode** cluster (Kubernetes 1.36) provisioned with Terraform.
Every command in this repository was **executed against a live cluster** and its **real
output recorded** — including the intended *failures* (NoCredentials, Forbidden,
AccessDenied, admission denials, network blocks) that prove each security control works.

> All secrets, tokens, and account IDs are redacted/masked. This repo is safe to read and
> reproduce in your own AWS account.

---

## What's inside

| Path | Contents |
|------|----------|
| **[`ARCHITECTURE.md`](./ARCHITECTURE.md)** | **Start here** — the map of every domain, the identity chains, and how it all fits together. |
| [`command-log/`](./command-log) | Every command we ran (28), each with a 3-point summary (purpose / Kubernetes effect / AWS service used), a line-by-line breakdown, and real output. |
| [`modules-docs/`](./modules-docs) | Concept deep-dives (the "why") with diagrams for each module. |
| [`images/`](./images) | Architecture & flow diagrams referenced by the docs. |
| [`workshop-tools/`](./workshop-tools) | Reference for the CLI tools used (kubectl, eksctl, helm, jq, k9s, …). |
| [`learning-path/`](./learning-path) | **Study kit** — Excel workbooks: a master learning path + progress tracker, and one per-module workbook (overview / steps / self-check). |
| `main.tf`, `eks-auto-2/`, `eks-private-cluster/`, `kube-bench/`, `devsecops/` | The Terraform that provisions the cluster(s) and supporting infrastructure. |

---

## Security domains covered

Each domain answers one clear question, layered for defense-in-depth:

| Question | Domain | Modules |
|----------|--------|---------|
| **Who can reach the cluster?** | Authentication / access | `aws-auth` ConfigMap, EKS **access entries**, **OIDC IdP** (Cognito) |
| **What can they do in Kubernetes?** | Authorization | **RBAC**, EKS access policies (cluster-admin/admin/edit/view + scope) |
| **What AWS can workloads reach?** | Pod → AWS identity | **IRSA**, **EKS Pod Identity** (+ session-tag ABAC) |
| **What may a pod be?** | Workload hardening | **Pod Security Admission**, **OPA/Gatekeeper** |
| **How is traffic & supply chain secured?** | Network & images | **Network Policies** (eBPF), VPC Lattice, mTLS, **Secrets Manager CSI**, **ECR/Inspector/signing** |
| **How do we detect & prove compliance?** | Detective / audit | **GuardDuty**, EKS audit logs + **Log Insights**, **kube-bench** CIS |

See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full flow and the end-to-end identity
chains.

---

## How to read it

1. Read **[`ARCHITECTURE.md`](./ARCHITECTURE.md)** for the big picture.
2. Open **[`command-log/README.md`](./command-log/README.md)** and follow commands **01 → 28
   in order** — each is self-contained and beginner-oriented.
3. When a command references a concept, jump to the matching file in
   [`modules-docs/`](./modules-docs).

---

## Highlights (real, verified outcomes)

- **IRSA & Pod Identity**: the same `aws s3 ls` that fails with `NoCredentials` succeeds once
  the pod gets its own scoped identity — with the injected env vars and decoded tokens shown.
- **Access entries**: three personas scoped to `cluster-admin` / `admin@team-a` /
  `view@team-a` with a single API call each — no hand-written RBAC.
- **Pod Security & Gatekeeper**: privileged pods rejected at admission (with the full
  violation list / `validation.gatekeeper.sh` denial).
- **Network Policies**: deny-by-default then allow only `client-one` — verified with a real
  eBPF `PolicyEndpoint` and a documented troubleshooting arc for EKS Auto Mode.
- **Secrets Manager CSI**: a secret mounted into a pod as a file via the CSI driver + IRSA.
- **Detective controls**: a live CloudWatch **Log Insights** query over the EKS audit log.

---

## Safety & cost notes

Some modules involve **account-level services** or **cost-bearing infrastructure**. These are
**documented with exact enablement commands but intentionally not enabled** here — turn them
on deliberately:
- Amazon **GuardDuty** (EKS Protection / Runtime Monitoring)
- Amazon **Inspector** / ECR **ENHANCED** scanning
- The **DevSecOps pipeline** (`devsecops/`)
- **VPC Lattice** (`eks-auto-2/`) and **mTLS + ACM Private CA**
- The **kube-bench** classic node group (`kube-bench/`)

---

## Prerequisites to reproduce

- An EKS **Auto Mode** cluster (this repo uses one named `eks-auto`), `kubectl`, `eksctl`,
  `helm`, and the **AWS CLI v2** configured with sufficient permissions.
- Terraform ≥ 1.3 to provision the infrastructure in the `*/` folders.

---

## License

Provided as-is for educational purposes. Review and adapt IAM policies, network posture, and
service enablement to your own security requirements before using in production.
