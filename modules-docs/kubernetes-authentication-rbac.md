# Module: Kubernetes Authentication & RBAC

This is a **concepts** module (no commands executed yet). It explains Role-Based Access
Control (RBAC) — the Kubernetes system that decides *what an authenticated identity is
allowed to do*. It sets up the next hands-on lesson where we create **3 IAM roles mapped
to 3 IAM groups**.

> Where this fits: the previous module ([`iam-groups-and-roles-aws-auth.md`](./iam-groups-and-roles-aws-auth.md))
> covered **authentication** (proving *who* you are, IAM → cluster). RBAC is about
> **authorization** (deciding *what* you can do once you're in).

---

## 1. What is RBAC?

From the official Kubernetes docs:

> Role-Based Access Control (RBAC) is a method of regulating access to computer or network
> resources based on the **roles** of individual users within an enterprise.

In short: instead of granting permissions to each person one-by-one, you define **roles**
(bundles of permissions) and assign identities to them.

---

## 2. The core logical components of RBAC

### Entity
A **group**, **user**, or **Service Account** — an identity that wants to execute certain
operations (actions) and requires permissions to do so.
- A **Service Account** represents an *application* (a workload/pod) rather than a human.

### Resource
The thing being accessed — a **Pod**, **Service**, or **Secret** — that the entity wants
to act on using certain operations.

### Role and ClusterRole
An RBAC **Role** or **ClusterRole** contains **rules** that represent a set of
permissions.

- Permissions are **purely additive** — there are **no "deny" rules**. (You grant; you
  never explicitly deny. If a permission isn't granted, it's simply not allowed.)
- A **Role** always sets permissions **within a particular Namespace** — you must specify
  the Namespace when you create it.
- A **ClusterRole** is **non-namespaced** (cluster-wide).

> They have different names because a Kubernetes object must be **either** namespaced
> **or** not — it can't be both.

### RoleBinding and ClusterRoleBinding
A **binding** is what actually *grants* a Role's permissions to one or more subjects
(users, groups, or Service Accounts).

- A **RoleBinding** grants permissions within a **specific Namespace**.
- A **ClusterRoleBinding** grants access **cluster-wide**.
- A RoleBinding may reference any **Role** in the same Namespace **or** reference a
  **ClusterRole** and bind it to just the RoleBinding's Namespace.
- To bind a ClusterRole to **all** Namespaces, use a **ClusterRoleBinding**.

---

## 3. Namespaces — security boundaries

**Namespaces** are an excellent way of creating **security boundaries**, and they provide
a unique scope for object names (two objects can share a name if they're in different
Namespaces).

They are intended for **multi-tenant environments** — creating "virtual Kubernetes
clusters" on the same physical cluster.

---

## 4. Putting it together: the mental model

```
   Entity (user/group/ServiceAccount)
            │  is granted by
            ▼
   RoleBinding  ──references──►  Role         (permissions in ONE namespace)
   ClusterRoleBinding ──ref──►  ClusterRole   (permissions cluster-wide)
            │
            ▼
   allowed operations on Resources (Pods, Services, Secrets, ...)
```

- **Role/ClusterRole** = *what* actions are allowed.
- **RoleBinding/ClusterRoleBinding** = *who* gets those actions, and *where* (namespace vs
  cluster-wide).

---

## 5. Why IAM Groups make this easier

If different teams need different kinds of cluster access, manually adding/removing access
per user per cluster is tedious and error-prone.

We can leverage **AWS IAM Groups** to easily add or remove users and grant them permission
to the whole cluster — or just part of it — depending on which group they belong to.

**Next lesson:** we will create **3 IAM roles** that we map to **3 IAM groups**, then wire
those into Kubernetes RBAC so group membership controls cluster access.

---

## 6. Beginner glossary recap

| Term | Namespaced? | Grants "what" or "who"? |
|------|-------------|-------------------------|
| **Role** | Yes (one namespace) | *What* actions (in that namespace) |
| **ClusterRole** | No (cluster-wide) | *What* actions (anywhere) |
| **RoleBinding** | Yes (one namespace) | *Who* gets a Role/ClusterRole, scoped to a namespace |
| **ClusterRoleBinding** | No (cluster-wide) | *Who* gets a ClusterRole, cluster-wide |
| **ServiceAccount** | Yes | An identity for an *application/pod* |
| **Namespace** | — | A security & naming boundary |
