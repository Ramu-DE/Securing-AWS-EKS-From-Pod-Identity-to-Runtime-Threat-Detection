# Command 09: Create Kubernetes namespaces + RBAC Roles/RoleBindings

```bash
# 1) Create the two namespaces (idempotent via dry-run | apply)
kubectl create namespace integration --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace development --dry-run=client -o yaml | kubectl apply -f -

# 2) development namespace: Role "dev-role" + RoleBinding to Kubernetes user "dev-user"
cat << EOF | kubectl apply -f - -n development
kind: Role
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-role
rules:
  - apiGroups: ["", "apps", "batch", "extensions"]
    resources: ["configmaps","cronjobs","deployments","events","ingresses","jobs",
                "pods","pods/attach","pods/exec","pods/log","pods/portforward",
                "secrets","services"]
    verbs: ["create","delete","get","list","patch","update","watch"]
---
kind: RoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: dev-role-binding
subjects:
- kind: User
  name: dev-user
roleRef:
  kind: Role
  name: dev-role
  apiGroup: rbac.authorization.k8s.io
EOF

# 3) integration namespace: same pattern, "integ-role" bound to user "integ-user"
```

> Concept background lives in
> [`modules-docs/kubernetes-authentication-rbac.md`](../../modules-docs/kubernetes-authentication-rbac.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Create the Kubernetes side of the access model: two namespaces (`development`, `integration`) and, in each, a **Role** + **RoleBinding** granting a Kubernetes user full access *within that namespace only*. |
| 2 | **What happens in Kubernetes** | **This is the first step that changes the cluster.** It creates 2 Namespaces, 2 Roles, and 2 RoleBindings. `dev-user` gets full rights in `development`; `integ-user` gets full rights in `integration`. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (the commands hit the EKS-hosted Kubernetes API server). No IAM/STS call here — but the `dev-user`/`integ-user` names are what the IAM roles will map to next. |

---

## 1. In one sentence

We finally build the **Kubernetes RBAC objects** that the IAM roles will map onto, so that
assuming `k8sDev` → acts as `dev-user` → has full access to *only* the `development`
namespace (and similarly for integration).

---

## 2. How this closes the chain

Earlier we built **User → Group → Role** in AWS IAM. Now we build the Kubernetes end:

```
IAM role k8sDev   ── (mapped later) ──►  Kubernetes user "dev-user"   ──► dev-role in "development" ns
IAM role k8sInteg ── (mapped later) ──►  Kubernetes user "integ-user" ──► integ-role in "integration" ns
```

The **RoleBinding** is the glue: it binds the Kubernetes user (`dev-user`) to the Role
(`dev-role`). Because it's a **Role/RoleBinding** (not Cluster*), the permissions apply
**only inside that one namespace**.

---

## 3. Background concepts (for beginners)

- **Namespace** = a virtual sub-cluster; a boundary for names and access.
- **Role** = a set of allowed actions (`verbs`) on resource types (`resources`) within API
  groups (`apiGroups`), scoped to one namespace.
- **RoleBinding** = grants a Role to subjects (here a `User`). Scoped to the namespace.
- **`--dry-run=client -o yaml | kubectl apply -f -`** = a trick to make namespace creation
  **idempotent**: it renders the namespace YAML without contacting the server, then
  `apply` creates-or-updates it (no error if it already exists, unlike `kubectl create`).
- **`cat << EOF | kubectl apply -f -`** = a "heredoc": feed the inline YAML between `<< EOF`
  and `EOF` straight into `kubectl apply` via stdin (`-f -` means "read from stdin").

---

## 4. What the Role grants

| Field | Value | Meaning |
|-------|-------|---------|
| `apiGroups` | `""`, `apps`, `batch`, `extensions` | Core + workload API groups. |
| `resources` | configmaps, deployments, pods, secrets, services, pods/exec, … | The object types the user can touch. |
| `verbs` | create, delete, get, list, patch, update, watch | Full read **and** write. |

Because it's a **Role** (not a ClusterRole), all of this applies **only** in the
namespace it's created in.

---

## 5. ⚠️ Security note — this "developer" Role is intentionally broad

This lab Role is broad on purpose, but two grants carry outsized blast radius in a real
cluster:

- **`secrets` (get/list)** → the holder can **read every credential** mounted in the
  namespace.
- **`pods/exec` + `pods/attach`** → the holder can **open a shell in any running pod**,
  bypassing image immutability and inheriting that pod's service-account token / IRSA /
  Pod Identity.

**Least-privilege practice:** split read vs. write verbs; drop `secrets` and `pods/exec`
unless the persona truly needs them; give a "viewer" only `get/list/watch` and add
mutating verbs only for an "editor".

---

## 6. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`)

```
=== Create namespaces ===
namespace/integration created
namespace/development created

=== development: Role + RoleBinding for dev-user ===
role.rbac.authorization.k8s.io/dev-role created
rolebinding.rbac.authorization.k8s.io/dev-role-binding created

=== integration: Role + RoleBinding for integ-user ===
role.rbac.authorization.k8s.io/integ-role created
rolebinding.rbac.authorization.k8s.io/integ-role-binding created
```
Exit status: `0`.

**Verification:**
```
=== Namespaces ===
NAME          STATUS   AGE
development   Active   11s
integration   Active   14s

=== development RBAC ===
role.rbac.authorization.k8s.io/dev-role            (created)
rolebinding.rbac.../dev-role-binding    ROLE: Role/dev-role

=== integration RBAC ===
role.rbac.authorization.k8s.io/integ-role          (created)
rolebinding.rbac.../integ-role-binding  ROLE: Role/integ-role
```

Both namespaces are `Active`, and each has its Role bound to the correct Kubernetes user.
The RBAC scaffolding is in place — the next step maps the IAM roles to these Kubernetes
users so the access takes effect.

---

## 7. Handy related commands

```bash
kubectl get ns                                        # List all namespaces
kubectl get role,rolebinding -n development           # RBAC objects in a namespace
kubectl describe role dev-role -n development          # Full rule detail
kubectl describe rolebinding dev-role-binding -n development   # Who is bound to what
kubectl auth can-i get pods -n development --as dev-user       # Test what a user can do
```
