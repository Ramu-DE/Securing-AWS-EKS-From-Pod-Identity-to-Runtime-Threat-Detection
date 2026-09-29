# Module: Amazon EKS Cluster Access Management Controls (Access Entries)

This module teaches **EKS access entries** — the modern, **API-driven replacement** for the
`aws-auth` ConfigMap mappings from the IAM Groups and Roles module
([`iam-groups-and-roles-aws-auth.md`](./iam-groups-and-roles-aws-auth.md)). Both grant IAM
principals access to the cluster; **access entries are what AWS recommends for new
clusters** (and what EKS Auto Mode uses internally for its nodes). Pairs with
[`command-log/commands/18-list-access-policies.md`](../command-log/commands/18-list-access-policies.md).

---

## 1. Two identity types that can access an EKS cluster

### A. IAM principal (role or user) — authenticates to IAM
Can be given **Kubernetes** permissions (to work with cluster objects) via **two methods**:
- **Access entries** — manage the Kubernetes permissions of IAM principals **from outside
  the cluster**, using the same tools you created the cluster with (EKS API/CLI/CFN/eksctl).
- **`aws-auth` ConfigMap** — manage them **from inside the cluster**. (You can't migrate
  entries EKS itself added, e.g. managed-node-group or Fargate roles.)

Can also be given **IAM** permissions to work with the EKS cluster/resources via the EKS
API, CLI, CloudFormation, Console, or eksctl. Nodes join by **assuming an IAM role**. The
**AWS IAM Authenticator** (running on the EKS control plane) provides this IAM→cluster
access.

### B. A user in your own OIDC provider — authenticates to your OIDC IdP
- Can be given **Kubernetes** permissions.
- **Cannot** be given IAM permissions for the EKS API/CLI/etc.

You can use **both** identity types with a cluster. Users configure their `kubectl` config
to reach cluster objects.

---

## 2. What EKS Access Management Controls add

A set of EKS APIs that **tightly integrate IAM identities with Kubernetes authn/authz**.
Benefits:
- Define authorized IAM principals and their Kubernetes permissions **directly through an
  EKS API**, during or after cluster creation.
- The **cluster-creator identity's** Kubernetes permissions can be **scoped down or
  removed** for compliance; control can always be restored to an account admin.
- Other AWS services can use it to **auto-obtain** permissions to run apps on the cluster.
- Simplifies managing clusters shared by multiple users/services.

Supported on EKS **v1.23+** clusters (new or updated), in all regions.

---

## 3. Two new concepts

### Access entry
A **cluster identity directly linked to an AWS IAM principal** (user or role) used to
authenticate to the cluster.

### Access policy
An **Amazon EKS-specific** policy that authorizes an access entry to perform specific
cluster actions. Key points:
- **Not** IAM entities — defined and managed by **Amazon EKS**.
- Only **predefined AWS-managed** access policies are supported.
- Provide permission sets for common use cases (admin, edit, read-only).

### The four lab policies (based on Kubernetes user-facing roles)
| Access policy | Maps to Kubernetes role |
|---------------|-------------------------|
| `AmazonEKSClusterAdminPolicy` | `cluster-admin` |
| `AmazonEKSAdminPolicy` | `admin` |
| `AmazonEKSEditPolicy` | `edit` |
| `AmazonEKSViewPolicy` | `view` |

(There are 30+ EKS-managed access policies in total; the list grows over time.)

---

## 4. Kubernetes authorizers — how allow/pass/deny works

Kubernetes chains multiple **authorizers** in sequence. Both **upstream RBAC** and the
**Amazon EKS authorizer** support **allow** and **pass** (but **not deny**):

```
request → upstream RBAC authorizer ── allow ──► ALLOWED (returned immediately)
                     │ can't decide (pass)
                     ▼
             EKS access-entry authorizer ── allow ──► ALLOWED
                     │ pass
                     ▼
        both passed → DENY (default)
```

- RBAC evaluates first; an **allow** returns immediately.
- If RBAC can't decide, it **passes** to the EKS authorizer.
- If **both pass**, the result is **deny**.

Only IAM principals with the right permissions can authorize *other* IAM principals. The
EKS authorizer uses only the IAM principal + the applied EKS **access policies**.

---

## 5. Cluster authentication modes (recap + detail)

| Mode | Meaning |
|------|---------|
| **`CONFIG_MAP`** | `aws-auth` ConfigMap **only** (the original mode). Cluster creator is the initial `kubectl` user. |
| **`API_AND_CONFIG_MAP`** | **Both** methods usable; each stores **separate** entries. *(This is what `eks-auto` uses.)* |
| **`API`** | **Access entries only** (EKS API/CLI/SDK/CFN/Console). |

> Migration `CONFIG_MAP → API_AND_CONFIG_MAP → API` is **one-way**. Switching to `API`
> disables the ConfigMap path (the `aws-auth` mappings stop having effect).

Each access entry has a **type**; you can combine an **access scope** (limit to a namespace)
with an **access policy** (reusable permission set), **or** use the **Standard** type with
Kubernetes RBAC groups for custom permissions.

---

## 6. Relation to what we already did

- In [command 10](../command-log/commands/10-configure-aws-auth-configmap.md) we used the
  **legacy `aws-auth` ConfigMap** to map `k8sAdmin/k8sDev/k8sInteg`.
- This module rebuilds that same idea with **access entries** — the recommended path,
  especially on **EKS Auto Mode** (whose own node roles are authorized via access
  entries, as we can see in `aws eks list-access-entries`).
