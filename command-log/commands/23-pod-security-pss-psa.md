# Command 23: Pod Security Standards / Admission (PSA) — enforce & warn demo

```bash
# (a) enforce=restricted namespace
kubectl create namespace psa-restricted --dry-run=client -o yaml | kubectl apply -f -
kubectl label --overwrite ns psa-restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted

# TEST 1: privileged pod  -> REJECTED   |  TEST 2: restricted-compliant pod -> ADMITTED

# (b) warn-only namespace (enforce=privileged, warn=restricted)
kubectl create namespace psa-warn --dry-run=client -o yaml | kubectl apply -f -
kubectl label --overwrite ns psa-warn \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/audit=restricted
# TEST 3: privileged pod -> ADMITTED but returns a Warning
```

> Concept background: [`modules-docs/pod-security-pss-psa.md`](../../modules-docs/pod-security-pss-psa.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Demonstrate native **Pod Security Admission**: label namespaces with a **Pod Security Standard** level + mode and watch PSA **reject**, **warn**, or **audit** pods accordingly. |
| 2 | **What happens in Kubernetes** | Creates namespaces `psa-restricted` / `psa-warn` with `pod-security.kubernetes.io/*` labels. PSA then **rejects** a privileged pod under `enforce=restricted`, **admits** a compliant one, and **admits-with-warning** a privileged pod under `warn=restricted`. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (the API server + its built-in PSA admission controller). **No other AWS service** — PSA is pure Kubernetes. |

---

## 1. In one sentence

Turn on Kubernetes' built-in pod hardening by labeling namespaces, and see `enforce` block
bad pods while `warn` merely flags them.

---

## 2. Background (for beginners)

- **Pod Security Standards (PSS)** = 3 levels: `privileged` (no limits), `baseline`
  (blocks obvious escalations), `restricted` (hardened best-practice).
- **Pod Security Admission (PSA)** = built-in controller that applies a PSS level to a
  **namespace** via labels, in three **modes**: `enforce` (reject), `audit` (log), `warn`
  (advisory message). No install needed on EKS.

---

## 3. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`).

### 3a. `enforce=restricted` namespace
```
namespace/psa-restricted created & labeled
  pod-security.kubernetes.io/enforce = restricted
  pod-security.kubernetes.io/warn    = restricted
  pod-security.kubernetes.io/audit   = restricted
```

### 3b. TEST 1 — privileged pod → **REJECTED**
```
Error from server (Forbidden): ... pods "bad-pod" is forbidden: violates PodSecurity "restricted:latest":
  privileged (container "c" must not set securityContext.privileged=true),
  allowPrivilegeEscalation != false (...must set allowPrivilegeEscalation=false),
  unrestricted capabilities (...must set capabilities.drop=["ALL"]),
  runAsNonRoot != true (...must set runAsNonRoot=true),
  seccompProfile (...must set seccompProfile.type to "RuntimeDefault" or "Localhost")
```
PSA blocked it and listed **every** violation — exactly what `enforce` should do.

### 3c. TEST 2 — restricted-compliant pod → **ADMITTED**
```
pod/good-pod created
...
good-pod   1/1   Running
```
The compliant pod (runAsNonRoot, drop ALL caps, no priv-esc, seccomp RuntimeDefault) is
admitted and runs.

### 3d. `psa-warn` namespace (enforce=privileged, warn=restricted) — TEST 3 → **ADMITTED + WARNING**
```
Warning: would violate PodSecurity "restricted:latest": privileged (...), allowPrivilegeEscalation != false (...),
  unrestricted capabilities (...), runAsNonRoot != true (...), seccompProfile (...)
pod/warn-pod created
...
warn-pod   0/1   ContainerCreating
```
Here `enforce=privileged` allows anything, but `warn=restricted` returns an advisory
**`Warning:`** and the pod is **still created**. This is the difference between **warn**
(nudge) and **enforce** (block).

---

## 4. What this proves — the mode matrix

| Namespace | enforce | warn | Privileged pod result | Compliant pod |
|-----------|---------|------|-----------------------|---------------|
| `psa-restricted` | restricted | restricted | ⛔ **Rejected** (with full violation list) | ✅ Admitted |
| `psa-warn` | privileged | restricted | ✅ Admitted **+ Warning** | ✅ Admitted |

> Recall the **PSA UX gotcha** (concept doc): `enforce` acts only on the Pod object, so a
> non-compliant **Deployment** is accepted while its Pods silently fail — which is exactly
> why we also set **`warn`** to surface violations at apply time.

---

## 5. Cleanup / handy commands

```bash
kubectl label ns <ns> pod-security.kubernetes.io/enforce=baseline --overwrite   # relax
kubectl get ns -L pod-security.kubernetes.io/enforce                            # see enforce level per ns
kubectl delete ns psa-restricted psa-warn                                       # cleanup demo
```
