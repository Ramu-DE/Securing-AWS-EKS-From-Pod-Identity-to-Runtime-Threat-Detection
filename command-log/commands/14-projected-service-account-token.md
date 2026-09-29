# Command 14: Inspect the projected Service Account OIDC token

```bash
# 1) List service accounts (modern K8s: no SECRETS column)
kubectl get sa

# 2) Create a sleep pod so we can exec into it
cat > eks-iam-test2.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: eks-iam-test2
spec:
  containers:
    - name: my-aws-cli
      image: amazon/aws-cli:latest
      command: ['sleep', '36000']
  restartPolicy: Never
EOF
kubectl apply -f eks-iam-test2.yaml
kubectl get pod

# 3) Inspect the projected volume in the pod spec
kubectl get pod eks-iam-test2 -oyaml

# 4) Read the projected OIDC token and decode it (paste payload into jwt.io)
kubectl exec -it eks-iam-test2 -- cat /var/run/secrets/kubernetes.io/serviceaccount/token
```

> Concept background lives in [`modules-docs/irsa.md`](../../modules-docs/irsa.md) and the
> full diagram walkthrough in
> [`modules-docs/irsa-complete-flow.md`](../../modules-docs/irsa-complete-flow.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Show the **Kubernetes plumbing that underpins IRSA**: every pod already gets a **projected, auto-rotating OIDC JWT** for its ServiceAccount. Understanding this token is the foundation for how IRSA later injects a *second* token for AWS. |
| 2 | **What happens in Kubernetes** | Creates a `sleep` pod (`eks-iam-test2`), then reads its **projected `serviceAccountToken`** volume mounted at `/var/run/secrets/kubernetes.io/serviceaccount/token`. Read-only inspection otherwise. |
| 3 | **Which AWS service is called/used** | **None directly.** This token's audience is the **Kubernetes API server**, not AWS. `kubectl` talks to **Amazon EKS**. The token's `iss` is the cluster's EKS-hosted **OIDC provider** — which AWS STS will later trust (that's the next step). |

---

## 1. In one sentence

Peek at the OIDC JWT Kubernetes automatically projects into every pod — the compliant,
short-lived, auto-rotating token that IRSA builds on.

---

## 2. Background: Kubernetes Service Accounts & token methods

A **ServiceAccount (SA)** is a **non-human identity** in the cluster. Pods use an SA's
credentials to authenticate (e.g. to the API server). Three ways to manage SA tokens:

| Method | Rotates/Expires? | Recommended? |
|--------|------------------|--------------|
| **TokenRequest API** | Yes (short-lived) | ✅ Recommended |
| **Token Volume Projection** (k8s ≥1.20) | Yes (kubelet rotates before expiry) | ✅ Recommended — *this is what we inspect here* |
| **SA Token Secrets** (static) | ❌ Never | ⛔ Not recommended (long-lived static creds) |

Since **Kubernetes 1.24**, the `LegacyServiceAccountTokenNoAutoGeneration` gate (on by
default) means Kubernetes **no longer auto-creates** a long-lived token Secret per SA.

---

## 3. Projected volumes & the ProjectedServiceAccountToken feature

A **projected volume** maps several sources into one directory. Sources can be:
`secret`, `downwardAPI`, `configMap`, and **`serviceAccountToken`**.

Since k8s 1.12, the **ProjectedServiceAccountToken** feature projects a **fully OIDC-
compliant JWT** (issued by the **TokenRequest API**) into each pod. These flags are on by
default on EKS — so every pod gets a compliant OIDC token automatically.

---

## 4. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`)

### 4a. Service accounts — note the missing SECRETS column
```
$ kubectl get sa
NAME      AGE
default   42h
```
On this modern cluster there is **no `SECRETS` column** at all. Pre-1.24 it showed the
count of auto-generated token Secrets. Its removal reflects that Kubernetes no longer
auto-creates a long-lived token Secret per SA.

### 4b. Pod created
```
$ kubectl get pod
NAME            READY   STATUS    RESTARTS   AGE
eks-iam-test1   0/1     Error     6 (...)    6m33s     # the NoCredentials pod from cmd 13, still looping
eks-iam-test2   1/1     Running   0          3s        # our new sleep pod
nginx-admin     1/1     Running   0          12m
```

### 4c. The projected volume (relevant fields from `-o yaml`)
```yaml
    volumeMounts:
    - mountPath: /var/run/secrets/kubernetes.io/serviceaccount   # base path for all sources
      name: kube-api-access-tqkq8
      readOnly: true
  serviceAccountName: default
  volumes:
  - name: kube-api-access-tqkq8
    projected:                       # <-- a PROJECTED volume, combining 3 sources:
      sources:
      - serviceAccountToken:
          expirationSeconds: 3607     # ~1h, kubelet rotates before expiry
          path: token                 # -> /var/run/secrets/.../token
      - configMap:
          name: kube-root-ca.crt      # -> ca.crt (cluster CA)
      - downwardAPI:
          items: [ { fieldPath: metadata.namespace, path: namespace } ]
```
So the token file is at `/var/run/secrets/kubernetes.io/serviceaccount/token`, alongside
`ca.crt` and `namespace`.

### 4d. The decoded token payload (REAL, from this cluster)
The raw token (1209 chars) starts with `eyJhbGciOiJSUzI1NiIs...`. Decoding the middle
(payload) segment:

```json
{
  "aud": ["https://kubernetes.default.svc"],
  "exp": 1790738824,
  "iat": 1790652424,
  "iss": "https://oidc.eks.us-west-2.amazonaws.com/id/5CC109EF2CCB404415FA350577E27AF5",
  "jti": "f06bda76-fa4c-4d41-b684-b0fa76bc3b60",
  "kubernetes.io": {
    "namespace": "default",
    "node": { "name": "i-09a9f9a994c16015e", "uid": "..." },
    "pod":  { "name": "eks-iam-test2",        "uid": "..." },
    "serviceaccount": { "name": "default",    "uid": "..." },
    "warnafter": 1790656031
  },
  "nbf": 1790652424,
  "sub": "system:serviceaccount:default:default"
}
```

---

## 5. Reading the important fields

| Field | Value here | Meaning |
|-------|-----------|---------|
| **`iss`** (issuer) | `https://oidc.eks.us-west-2.amazonaws.com/id/5CC1...7AF5` | The cluster's **OIDC provider** URL. Used to **verify** the token later. This is the same issuer registered as the IAM OIDC provider for IRSA. |
| **`aud`** (audience) | `https://kubernetes.default.svc` | The **Kubernetes API server** address. This token is only accepted by the API server — **not** by AWS. |
| **`sub`** (subject) | `system:serviceaccount:default:default` | The identity: SA `default` in namespace `default`. (This is exactly the value an IRSA trust policy's `sub` condition matches on.) |
| **`exp` / `iat` / `nbf`** | unix timestamps | Expiry / issued-at / not-before — the token is **time-bound** and rotated. |

> **Security tip:** because the projected token targets the **Kubernetes API server**, if a
> pod's workload never calls the API server you can avoid mounting it entirely with
> `automountServiceAccountToken: false` in the pod spec — reducing exposure.

---

## 6. Why this matters for IRSA (the bridge to the next step)

This projected token authenticates to the **Kubernetes API server** (`aud =
kubernetes.default.svc`) — **not** to AWS. To call AWS APIs we need a *second* token whose
audience is **AWS STS**.

That's what the **AWS identity webhook** (preinstalled on EKS) does: it listens for
create-pod calls and **injects an additional token** (plus `AWS_ROLE_ARN` /
`AWS_WEB_IDENTITY_TOKEN_FILE`) for AWS use. That second token — combined with this
ServiceAccount foundation — is what **enables IRSA**. We'll see it in action next.

---

## 7. Cleanup / handy commands

```bash
kubectl exec -it eks-iam-test2 -- env | grep AWS      # (no AWS_* vars yet — IRSA not wired)
kubectl get pod eks-iam-test2 -o yaml                 # Full spec incl. projected volume
kubectl delete pod eks-iam-test2                      # Cleanup the sleep pod
kubectl delete pod eks-iam-test1                      # Cleanup the earlier failing pod
```
