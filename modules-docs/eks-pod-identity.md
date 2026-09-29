# Module: Amazon EKS Pod Identity

This is a **concepts** module (no commands yet). It introduces **EKS Pod Identity** — the
newer, EKS-native way to give pods AWS permissions — and compares it head-to-head with
**IRSA** (previous module). It sets up the hands-on Pod Identity lab that follows.

> Where this fits: IRSA ([`irsa.md`](./irsa.md)) uses **OIDC federation**. Pod Identity
> achieves the same goal — a pod-scoped IAM identity — but with a **simpler,
> EKS-integrated** workflow and no per-cluster OIDC provider.

---

## 1. Two ways to grant AWS IAM permissions to EKS workloads

Amazon EKS provides **two** mechanisms:

### 1. IAM Roles for Service Accounts (IRSA)
Fine-grained IAM permissions for Kubernetes apps. Built to support **many** deployment
options (EKS, **EKS Anywhere**, **Red Hat OpenShift Service on AWS**, self-managed k8s on
EC2). Because of that portability, IRSA is built on **foundational AWS services (IAM +
OIDC)** and takes **no direct dependency** on the EKS API.

### 2. EKS Pod Identity
A simplified workflow for authenticating applications to AWS resources. **EKS-only**, so
it can integrate directly with the EKS service — fewer steps, configured straight through
the **EKS console, API, or CLI**.

---

## 2. What EKS Pod Identity adds

- **Reuse an IAM role across multiple EKS clusters** — no per-cluster trust-policy edits.
- **Reuse permission policies across IAM roles.**
- **Attribute/tag-based access** — credentials include **role session tags** (cluster
  name, namespace, service account name), enabling access decisions based on matching
  tags.

The big administrative win: you **no longer switch between EKS and IAM** or run privileged
IAM operations per cluster. One role can serve the same app in many clusters **without**
updating its trust policy.

---

## 3. How EKS Pod Identity works — the workflow

```
1. Create an IAM role with the required permissions, and set the trust policy
   service principal to  pods.eks.amazonaws.com  (NOT an OIDC provider).
2. Install the EKS Pod Identity Agent add-on.
   └── On EKS Auto Mode this agent is BUILT-IN — no installation step needed.
3. Create a Pod Identity association: map the role → a ServiceAccount in a namespace.
4. Any new pod using that ServiceAccount automatically receives IAM credentials
   (EKS injects the AWS_* env vars for the SDK/CLI).
```

Key differences from IRSA in this flow:
- Trust policy principal is **`pods.eks.amazonaws.com`** (an EKS service principal), not a
  cluster-specific OIDC provider ARN.
- The **association** (role ↔ SA ↔ namespace ↔ cluster) lives in EKS, so the *same role*
  can be associated in many clusters unchanged.

---

## 4. EKS Pod Identity vs. IRSA — side by side

| Dimension | **EKS Pod Identity** | **IRSA** |
|-----------|----------------------|----------|
| **Role extensibility** | No trust-policy update per new cluster. | Must add each cluster's OIDC provider endpoint to the trust policy. |
| **Cluster scalability** | No IAM OIDC provider to set up. | Needs an IAM OIDC provider. Default limit **100 OIDC providers/account**. |
| **Role scalability** | No SA↔role trust relationship needed in the trust policy. | Must define SA↔role trust in the policy. **Max ~8** trust relationships per policy (size limit). |
| **Role reusability** | STS creds include **role session tags** (cluster/namespace/SA) → tag-based access control across clusters. | No STS session tags — reuse works, but every pod gets **all** the role's permissions. |
| **Environments** | **Amazon EKS only.** | EKS, **EKS Anywhere**, **ROSA**, self-managed k8s on EC2. |
| **EKS versions** | Kubernetes **1.24+**. | All supported EKS versions. |

---

## 5. Which one should you choose?

- **Prefer EKS Pod Identity for new workloads on EKS.** It removes the per-cluster OIDC
  provider, keeps role trust policies **portable** across clusters, supports **role
  session tags** for attribute-based access control, and on **EKS Auto Mode the agent is
  built-in** (nothing to install).
- **Choose IRSA when** you need the same mechanism **outside EKS** (EKS Anywhere, ROSA,
  self-managed k8s on EC2), or on **EKS versions earlier than 1.24**.
- **Both are fully supported, and a single cluster can use both at once.**

> Relevance to our cluster: `eks-auto` runs **EKS Auto Mode**, so the **Pod Identity Agent
> is already built in** — the upcoming lab skips the add-on install step entirely.

---

## 6. Beginner glossary

| Term | Meaning |
|------|---------|
| **Service principal** | An AWS service allowed to assume a role. For Pod Identity it's `pods.eks.amazonaws.com`. |
| **Pod Identity association** | The EKS-managed mapping of `IAM role → ServiceAccount → namespace → cluster`. |
| **Role session tags** | Key/value tags attached to the temporary STS session (here: cluster, namespace, SA) usable in IAM policy conditions for **ABAC** (attribute-based access control). |
| **Pod Identity Agent** | The component that fetches/serves credentials to pods; built into EKS Auto Mode. |
