# Command 24: Install OPA Gatekeeper and enforce a custom admission policy

```bash
# (a) Install Gatekeeper via Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system --create-namespace --wait

# (b) ConstraintTemplate (Rego rule) — deny privileged containers
kubectl apply -f - <<'EOF'
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata: { name: k8spspprivilegedcontainer }
spec:
  crd: { spec: { names: { kind: K8sPSPPrivilegedContainer } } }
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package k8spspprivileged
      violation[{"msg": msg}] {
        c := input.review.object.spec.containers[_]
        c.securityContext.privileged
        msg := sprintf("Privileged container is not allowed: %v, securityContext: %v", [c.name, c.securityContext])
      }
EOF

# (c) Constraint (instance) — enforce on Pods in namespace opa-test
kubectl apply -f - <<'EOF'
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sPSPPrivilegedContainer
metadata: { name: psp-privileged-container }
spec:
  match:
    kinds: [{ apiGroups: [""], kinds: ["Pod"] }]
    namespaces: ["opa-test"]
EOF

# (d) Test: privileged pod -> DENIED ; normal pod -> ALLOWED
```

> Concept background: [`modules-docs/opa-gatekeeper.md`](../../modules-docs/opa-gatekeeper.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Install **OPA Gatekeeper** and enforce a **custom** admission policy (deny privileged containers) — going beyond PSA's fixed Pod Security Standards. |
| 2 | **What happens in Kubernetes** | Deploys Gatekeeper (webhook + audit) in `gatekeeper-system`; registers a **ConstraintTemplate** (new CRD) + **Constraint**; the validating webhook then **rejects** a privileged pod and **allows** a compliant one in `opa-test`. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (API server + admission webhook); Helm pulls the chart from the public OPA repo and images from public registries. **No other AWS service** — Gatekeeper is pure Kubernetes. |

---

## 1. In one sentence

Add programmable, org-specific admission rules to the cluster with OPA Gatekeeper, and
prove a privileged-container ban works.

---

## 2. Background (for beginners)

- **OPA** = a general policy engine; rules are written in **Rego**, decisions are JSON.
- **Gatekeeper** = OPA packaged as a Kubernetes **admission webhook** + CRDs.
- **ConstraintTemplate** = the reusable rule (Rego) — registers a new policy *kind*.
- **Constraint** = an instance of that kind that says *where* it applies (`match`).
- **Admission webhook** = the API server asks Gatekeeper to allow/deny each write; a denied
  object is never created.

---

## 3. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`).

### 3a. Gatekeeper installed (Helm v3.21.2)
```
Release "gatekeeper": STATUS: deployed
$ kubectl -n gatekeeper-system get pods
gatekeeper-audit-...                1/1   Running
gatekeeper-controller-manager-...   1/1   Running
# CRDs registered: constrainttemplates, constraints, etc.  (deployments Available)
```

### 3b. Template + Constraint created
```
constrainttemplate.../k8spspprivilegedcontainer created
crd .../k8spspprivilegedcontainer.constraints.gatekeeper.sh  condition met (established)
k8spspprivilegedcontainer.../psp-privileged-container created
namespace/opa-test created
```

### 3c. TEST 1 — privileged pod → **DENIED** (matches the workshop screenshot)
```
Error from server (Forbidden): error when creating "STDIN":
admission webhook "validation.gatekeeper.sh" denied the request:
[psp-privileged-container] Privileged container is not allowed: nginx, securityContext: {"privileged": true}
```

### 3d. TEST 2 — non-privileged pod → **ALLOWED**
```
pod/normal-pod created
$ kubectl -n opa-test get pods
normal-pod   ...   ContainerCreating/Running
```

### 3e. Audit
```
$ kubectl get k8spspprivilegedcontainer psp-privileged-container -o jsonpath='{.status.totalViolations}'
0
```
No **pre-existing** violators in scope (the audit pod scans existing objects; new bad pods
are blocked at admission before they can exist).

---

## 4. What this proves

Gatekeeper's `validation.gatekeeper.sh` webhook enforced a **custom** Rego rule the built-in
PSA doesn't provide as a standalone knob — the request was blocked **before** the pod was
created, exactly like the workshop's reference screenshot. The same pattern extends to any
policy: required labels, allowed registries, banning `:latest`, replica limits, etc.

---

## 5. Cleanup / handy commands

```bash
kubectl get constrainttemplates
kubectl get constraints                      # all constraint instances
kubectl describe k8spspprivilegedcontainer psp-privileged-container   # violations/status
# Cleanup:
kubectl delete k8spspprivilegedcontainer psp-privileged-container
kubectl delete constrainttemplate k8spspprivilegedcontainer
kubectl delete ns opa-test
helm uninstall gatekeeper -n gatekeeper-system && kubectl delete ns gatekeeper-system
```
