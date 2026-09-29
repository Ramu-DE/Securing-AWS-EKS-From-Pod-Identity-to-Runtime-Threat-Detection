# Module: Using AWS IAM Groups and Roles to Manage Kubernetes Cluster Access

In this module we learn how to simplify access to different parts of the Kubernetes
cluster depending on AWS IAM Roles. It pairs with the hands-on commands logged in
[`command-log/commands/05-check-ide-role-in-aws-auth.md`](../command-log/commands/05-check-ide-role-in-aws-auth.md).

---

## 1. This module uses the *legacy* aws-auth ConfigMap — read this first

The role → group → RBAC mapping you build here is wired into the cluster through the
**`aws-auth` ConfigMap**, the *original* EKS authorization mechanism.

For new clusters — and for **EKS Auto Mode** specifically — AWS now recommends **EKS
access entries**, an API-driven mechanism that needs no ConfigMap edit and no
`system:masters` shortcut.

This module teaches `aws-auth` because:
- It remains **supported** (while the cluster's authentication mode still includes
  `CONFIG_MAP`), and
- It is the mechanism you will meet on **most existing clusters**.

> The *Cluster Access Management Controls* module rebuilds the same
> roles → mappings → RBAC pattern with **access entries**, so you can compare the legacy
> and modern approaches side by side.
>
> In our Terraform, the `eks-auto` cluster uses
> `authentication_mode = "API_AND_CONFIG_MAP"` — that's what keeps this legacy lab
> working.

---

## 2. Who becomes the first cluster admin?

When an Amazon EKS cluster is created, the **IAM entity (user or role) that creates the
cluster** is *permanently* added to the Kubernetes RBAC authorization table as the
administrator. That entity is automatically part of the Kubernetes RBAC group
**`system:masters`** and is bound to the default ClusterRole **`cluster-admin`**.

- **`cluster-admin`** is the most powerful role — super-user access to perform any action
  on any resource.
  - In a **ClusterRoleBinding**: full control over every resource in the cluster and all
    namespaces.
  - In a **RoleBinding**: full control over every resource in that binding's namespace,
    including the namespace itself.

> **WARNING:** It is highly recommended **not** to add any Kubernetes user to the
> `system:masters` group unless it is truly necessary.

The identity of this creator entity **isn't visible in your cluster configuration**, so
it is important to note *which* entity created the cluster and **never delete it**.

Initially, **only** the IAM entity that created the cluster can call the Kubernetes API
server with `kubectl`. If you created the cluster from the console, the same IAM
credentials must be in the AWS SDK credential chain when you run `kubectl`. After the
cluster exists, you can grant other IAM entities access.

---

## 3. Key terms (beginner glossary)

| Term | Meaning |
|------|---------|
| **RBAC** | Role-Based Access Control — Kubernetes' system of Roles + Bindings that decide who can do what. |
| **ConfigMap** | A Kubernetes object that stores configuration data as key/value pairs. `aws-auth` is a specific ConfigMap that maps IAM identities to Kubernetes users/groups. |
| **`kube-system` namespace** | The namespace where core cluster components (and the `aws-auth` ConfigMap) live. |
| **ClusterRole / ClusterRoleBinding** | A role (and its assignment) that applies cluster-wide across all namespaces. |
| **`system:masters`** | A built-in RBAC group whose members get full `cluster-admin` power. |

---

## 4. What the hands-on part does

1. **Identify the IDE's IAM role** — the role attached to the code-server (VS Code)
   instance, which is the identity that created and authenticates to the cluster.
2. **Check whether that role is listed in the `aws-auth` ConfigMap** in `kube-system`.

See the command log for the exact commands, explanations, and the real result in this
environment (which is itself instructive — see the note about access entries there).
