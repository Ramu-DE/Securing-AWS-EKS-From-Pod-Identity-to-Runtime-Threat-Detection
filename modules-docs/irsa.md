# Module: IAM Roles for Service Accounts (IRSA)

This document captures the **concepts** behind IRSA — how to give a *pod* (not a node) its
own AWS identity. It pairs with the hands-on demo logged in
[`command-log/commands/13-irsa-nocredentials-demo.md`](../command-log/commands/13-irsa-nocredentials-demo.md).

---

## 1. IRSA vs. EKS Pod Identity — which should you use?

- **IRSA** is the **original** mechanism for giving pods an AWS identity and is **still
  fully supported**.
- Since **late 2023**, AWS recommends **EKS Pod Identity** as the default for **new**
  workloads: no per-cluster IAM OIDC provider, no OIDC endpoint in the role trust policy,
  and the **Pod Identity Agent is built in on EKS Auto Mode**.
- **Choose IRSA when** you need the same identity mechanism **outside EKS** (EKS Anywhere,
  ROSA, self-managed Kubernetes on EC2) or on cluster versions **before 1.24**.

> We teach **IRSA first** because it exposes the underlying **OIDC/token machinery** that
> Pod Identity abstracts away — the next module builds on this understanding.

---

## 2. The security challenge IRSA solves

A common challenge: **how do you grant a containerized workload permission to access an
AWS service or resource?**

IAM provides fine-grained, least-privilege access control — but IAM needs an **identity**
to authenticate. The hard part is **providing an identity to a Kubernetes workload** that
IAM can use.

### The demo that exposes the problem
We deploy a pod that just runs `aws s3 ls`. With **no** identity attached, it fails with:

```
aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials.
```

The pod has no IAM role on its service account, and on **EKS Auto Mode** a pod's access to
the **EC2 Instance Metadata Service (IMDS)** — and therefore the node's instance-profile
credentials — is **blocked by default**. So the AWS CLI credential provider chain finds
**nothing** and fails with `NoCredentials`.

### Auto Mode vs. traditional cluster (important distinction)
| Cluster type | Pod without IRSA gets… | Typical failure |
|--------------|------------------------|-----------------|
| **EKS Auto Mode** | *no* credentials (IMDS blocked) | **`NoCredentials`** |
| Classic (self/managed nodes) | falls back to the **node instance profile** via IMDS | **`AccessDenied`** (node role lacks S3) |

Auto Mode's behavior is a **stronger security posture**: pods **cannot silently inherit
the node's permissions**. Either way the fix is the same — **give the pod its own
identity** instead of relying on the node.

### Why not just use the node's instance profile?
Because it violates **least privilege**: those permissions live at the **EC2 node** level,
so **every** pod on that node would gain the same access. We want permissions scoped to
the **pod**.

### Why not inject credentials via Secrets / env vars?
Not secure, and you'd have to manage the credential **lifecycle** (rotation, revocation)
yourself. **Not recommended.**

---

## 3. What IRSA provides

Instead of distributing AWS credentials to containers or relying on the EC2 instance
profile, you **associate an IAM Role with a Kubernetes Service Account**, and configure
Pods to **use that Service Account**. Any pod using that Service Account then gets the
role's AWS permissions — automatically and temporarily.

### Benefits
- **Least privilege** — scope IAM permissions to a Service Account; only pods using it get
  those permissions. No need to over-grant the node role.
- **Credential isolation** — a container can only get credentials for the role tied to
  *its* Service Account; never another pod's.
- **Auditability** — access/events are logged via **AWS CloudTrail** for retrospective
  auditing.

> Mental model: RBAC governs access to **Kubernetes** resources; IRSA/IAM governs access
> to **AWS** services. A pod can use both at once.

---

## 4. IRSA components & how it works

IRSA relies on **OIDC (OpenID Connect) federation**:

1. The EKS cluster exposes an **OIDC issuer URL**.
2. You register that issuer as an **IAM OIDC identity provider**.
3. Kubernetes projects a **signed service-account token** (a JWT) into the pod.
4. The pod's AWS SDK/CLI calls **STS `AssumeRoleWithWebIdentity`**, presenting that token.
5. STS validates it against the OIDC provider and the role's **trust policy**, then returns
   **temporary credentials** scoped to the role.

---

## 5. Enabling IRSA — the three procedures (next steps)

1. **Create an IAM OIDC provider** for the EKS cluster.
2. **Configure a Kubernetes Service Account to assume an IAM role** (annotate the SA with
   the role ARN; set the role's trust policy to the OIDC provider).
3. **Configure pods to use that Service Account.**

---

## 6. ⚠️ Security note — avoid `:latest` image tags

Every sample pod in this module uses `image: amazon/aws-cli:latest` for simplicity. In
production, **do not deploy mutable `:latest` tags**:
- Pin an **immutable version tag** (e.g. `amazon/aws-cli:2.15.0`), or better
- Pin a **content digest** (`amazon/aws-cli@sha256:...`).

Mutable tags make deployments **non-reproducible** and are a **supply-chain risk** — the
image behind the tag can change without warning.
