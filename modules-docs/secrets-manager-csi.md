# Module: Mounting Secrets from AWS Secrets Manager (Secrets Store CSI + ASCP)

Mount secrets from **AWS Secrets Manager** (and SSM Parameter Store) into pods as files,
using the **Secrets Store CSI Driver** + the **AWS Secrets and Configuration Provider
(ASCP)**, with pod-scoped AWS access via **IRSA** (or Pod Identity). Pairs with the
hands-on demo in
[`command-log/commands/26-secrets-manager-csi.md`](../command-log/commands/26-secrets-manager-csi.md).

---

## 1. Why mount secrets from Secrets Manager?

- **No secrets baked into images or manifests** — the secret lives in Secrets Manager
  (encrypted, rotated, audited), not in a Kubernetes Secret checked into git.
- **Central management + rotation** — update once in Secrets Manager; pods get the current
  value on (re)mount.
- **Pod-scoped access** — combined with IRSA/Pod Identity, only pods whose ServiceAccount
  is allowed can read a given secret (least privilege), and IAM/CloudTrail audit applies.

---

## 2. The components

| Component | Role |
|-----------|------|
| **Secrets Store CSI Driver** | A CSI driver (DaemonSet) that mounts a special volume into pods and asks a *provider* to fetch the contents. |
| **AWS provider (ASCP)** | The provider (DaemonSet) that actually calls AWS Secrets Manager / SSM using the pod's AWS identity. |
| **SecretProviderClass** | A namespaced CRD describing *which* secrets to fetch (names, types, JMESPath, sync-to-k8s-Secret). |
| **IRSA / Pod Identity** | Gives the pod's ServiceAccount an IAM role scoped to read only the required secret ARN. |

---

## 3. How a mount works

```
Pod (SA=secrets-sa) mounts a CSI volume (secretProviderClass=...)
   │
   ▼
Secrets Store CSI Driver  ──►  AWS provider (ASCP)
                                  │ uses the SA's IRSA/Pod-Identity credentials
                                  ▼
                         AWS Secrets Manager (GetSecretValue on the allowed ARN)
                                  │
                                  ▼
       secret written as a FILE into the pod at the mountPath (e.g. /mnt/secrets/<name>)
```

The application just reads a **file** — it never handles AWS credentials or calls Secrets
Manager directly.

---

## 4. Two configuration gotchas (learned live — see command log)

1. **`tokenRequests` on the CSIDriver is required.** The driver must be installed with
   `tokenRequests[0].audience=sts.amazonaws.com` so it can obtain a bound SA token for the
   provider to exchange for AWS creds. Without it: *"serviceAccount.tokens not provided —
   ensure tokenRequests is configured in CSIDriver"*.
2. **The ServiceAccount needs a resolvable IAM role.** The AWS provider resolves **IRSA**
   (the `eks.amazonaws.com/role-arn` annotation on the SA) reliably. Without a role the
   mount fails: *"An IAM role must be associated with service account …"*. (Pod Identity
   support depends on the provider version; IRSA is the dependable path.)

---

## 5. Least-privilege IAM

Scope the IAM policy to the **specific secret ARN**, not `*`:
```json
{ "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue","secretsmanager:DescribeSecret"],
  "Resource": "arn:aws:secretsmanager:us-west-2:<acct>:secret:eks-workshop-db-secret-XXXX" }
```
Attach it to a **per-ServiceAccount** IRSA role so only that workload can read that secret.

---

## 6. Best practices

- **Never** commit secrets to git or bake into images; use this CSI flow (or External
  Secrets Operator) instead.
- Scope IAM to exact secret ARNs; one role per workload/SA.
- Prefer **files over env vars** for secrets (env vars leak via `/proc`, crash dumps, child
  processes).
- Enable **rotation** in Secrets Manager; the CSI driver can be configured to rotate mounted
  values (`enable-secret-rotation`).
- Optionally **sync to a Kubernetes Secret** (`syncSecret`) only if a workload needs it as
  an env var — but that copies the value into etcd, so weigh the tradeoff.

---

## 7. Relation to the rest of the workshop

- This reuses the **IRSA** identity mechanism (module cmd 13–15): the CSI provider assumes
  the SA's IRSA role to read the secret — the same OIDC federation, applied to Secrets
  Manager access.
- Complements **Pod Identity** (cmd 16–20) — both give pods scoped AWS access; here it's
  specifically for pulling secrets at mount time.
