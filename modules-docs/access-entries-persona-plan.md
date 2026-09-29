# Module: Create Access Entries and Policies (persona plan)

This is the **overview/plan** for the access-entries hands-on section. It defines three
personas and the access policy each will get. No commands are run in this intro; the
executed steps will be logged under `command-log/commands/` as they arrive.

> This is the **modern (access-entries) rebuild** of the same idea we did with the legacy
> `aws-auth` ConfigMap in the IAM Groups and Roles module (commands 06–11). Concept
> reference: [`eks-access-management-controls.md`](./eks-access-management-controls.md).

---

## 1. The three personas

| Persona (IAM group) | Who they are | Access they need |
|---------------------|--------------|------------------|
| **k8sClusterAdmin** | Cluster administrators | **Complete admin** access to the whole cluster. |
| **k8sTeamADev** | Developers for project A | **Admin** access to their namespace **`team-a`** only. |
| **k8sTeamATest** | Testers for project A | **Read-only** access to their namespace **`team-a`** only. |

---

## 2. The three IAM roles → access policies

| IAM role | Assumed by group | EKS access policy | Scope |
|----------|------------------|-------------------|-------|
| **k8sClusterAdmin** | `k8sClusterAdmin` | `AmazonEKSClusterAdminPolicy` (`cluster-admin`) | cluster-wide |
| **k8sTeamADev** | `k8sTeamADev` | `AmazonEKSAdminPolicy` (`admin`) | namespace `team-a` |
| **k8sTeamATest** | `k8sTeamATest` | `AmazonEKSViewPolicy` (`view`) | namespace `team-a` |

The access policies are the EKS-managed ones confirmed in
[command 18](../command-log/commands/18-list-access-policies.md).

---

## 3. How this differs from the aws-auth approach (commands 06–11)

| Step | Legacy (`aws-auth`) | Modern (**access entries**) |
|------|---------------------|-----------------------------|
| Grant cluster access | Add a `mapRoles` entry in the `aws-auth` ConfigMap | **`aws eks create-access-entry`** for the IAM principal |
| Grant permissions | Map to a K8s group + hand-written Role/RoleBinding, or `system:masters` | **`aws eks associate-access-policy`** with a managed access policy + **access scope** (cluster or namespace) |
| Where managed | Inside the cluster (ConfigMap) | Outside the cluster (EKS API) |
| Namespace scoping | Via Kubernetes RBAC objects you author | Built into the **access scope** of the association |

**Net effect:** access entries let you express "this IAM role gets *admin* on namespace
`team-a`" in **one EKS API call** — no hand-written Role/RoleBinding, no `system:masters`
shortcut.

---

## 4. Expected end-to-end chain (for each persona)

```
IAM User → IAM Group (assume-role policy) → IAM Role
   → EKS access entry (links the role as a cluster identity)
   → associated EKS access policy + access scope (cluster-wide or namespace team-a)
   → effective Kubernetes permissions
```

The upcoming commands will: create the IAM roles/groups, create an **access entry** per
role, and **associate** the matching access policy with the right **access scope**. Each
will be logged with its 3-point summary (purpose / Kubernetes effect / AWS service used)
and real output.
