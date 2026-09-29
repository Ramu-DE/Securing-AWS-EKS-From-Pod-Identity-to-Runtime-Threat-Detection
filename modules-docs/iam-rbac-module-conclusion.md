# Module Conclusion: Managing EKS Access with IAM Groups + Kubernetes RBAC

## The core takeaway

In this module, we have seen how to configure Amazon EKS to provide **finer-grained
access** to users by **combining AWS IAM Groups and Kubernetes RBAC**. You can create
different groups depending on your needs, configure their associated RBAC access in your
cluster, and simply **add or remove users from the group to grant or revoke access** to
your cluster.

Users only have to configure their AWS CLI in order to **automatically retrieve their
associated rights** in your cluster — no manual credential juggling per request.

---

## What we built, end to end

We assembled a complete, layered access-control chain and proved it works:

```
IAM User  →  IAM Group  →  IAM Role  →  aws-auth mapping  →  K8s User  →  RoleBinding  →  Role  →  Namespace-scoped access
(PaulAdmin)  (k8sAdmin)   (k8sAdmin)    (role→admin)         (admin)      (—)            (—)      (system:masters = all)
(JeanDev)    (k8sDev)     (k8sDev)      (role→dev-user)      (dev-user)   (dev-role-...)  (dev-role)   (development ns only)
(PierreInteg)(k8sInteg)   (k8sInteg)    (role→integ-user)    (integ-user) (integ-role-...)(integ-role) (integration ns only)
```

Each layer has a single, clear responsibility:

| Layer | Owner | Responsibility |
|-------|-------|----------------|
| IAM User | AWS IAM | Who the person is (long-term identity). |
| IAM Group | AWS IAM | Bulk membership; policy to **assume** one role. |
| IAM Role | AWS IAM | An assumable, permission-less "cluster access ticket." |
| `aws-auth` ConfigMap | Kubernetes (kube-system) | Translates an IAM role ARN → a Kubernetes username/group. |
| Role / RoleBinding | Kubernetes RBAC | *What* the K8s user may do, and *where* (namespace scope). |

---

## Why this design is powerful

### 1. Access management becomes a one-step operation
To onboard or offboard a person you **add or remove them from an IAM group** — nothing
else changes. You never touch the cluster, the `aws-auth` ConfigMap, or any RBAC object.
This scales cleanly from 3 users to thousands.

### 2. Separation of duties / single source of truth
- **AWS IAM** answers *"who are you and which access-role may you assume?"* (authentication
  + coarse gating).
- **Kubernetes RBAC** answers *"what may that identity actually do inside the cluster?"*
  (fine-grained authorization).

Mapping the **role** (not individual users) into `aws-auth` means the cluster config stays
stable while people churn in the IAM group.

### 3. Least privilege by namespace
`dev-user` and `integ-user` are confined to a single namespace each. We saw the RBAC
authorizer return **`Forbidden`** the moment a persona reached outside its namespace —
concrete proof the boundary is enforced, not just intended.

### 4. Temporary credentials, not standing keys
Because access flows through `sts:AssumeRole`, the credentials `kubectl` actually uses are
**short-lived STS session tokens**, not the user's long-term keys. Shorter-lived
credentials shrink the blast radius if anything leaks.

---

## Security caveats worth remembering

- **`:root` trust policy** — used here for lab simplicity, it lets *any* principal in the
  account (with `sts:AssumeRole`) assume these roles. In production, scope the trust policy
  to specific principals or group ARNs. **Never leave `:root` on a role mapping to
  `system:masters`.**
- **`system:masters` is super-user** — the `k8sAdmin`→`admin` mapping grants unrestricted
  cluster power. Add users to it only when truly necessary.
- **Broad "developer" Role** — our `dev-role`/`integ-role` granted `secrets` (read every
  credential) and `pods/exec`/`pods/attach` (shell into any pod, inheriting its identity).
  Real personas should split read vs. write verbs and drop these unless genuinely needed.
- **Credentials on disk** — saving user keys to `/tmp/*.json` and `~/.aws/credentials` was
  a lab convenience. Never store privileged, long-term credentials on the filesystem in
  production; prefer SSO / IAM Identity Center, short-lived sessions, or Pod Identity/IRSA
  for workloads.
- **Legacy vs. modern mechanism** — this module used the **`aws-auth` ConfigMap**, which
  remains supported while the cluster's authentication mode includes `CONFIG_MAP`. For new
  clusters — and for **EKS Auto Mode** specifically — AWS recommends **EKS access
  entries**, an API-driven mechanism that needs no ConfigMap edit and no `system:masters`
  shortcut. The *Cluster Access Management Controls* module rebuilds this exact pattern
  with access entries so you can compare them side by side.

---

## How it connects to the rest of the workshop

- We observed **EKS Auto Mode** launch a data-plane node on demand only once workloads
  (our test pods) were scheduled — reinforcing that Auto Mode manages compute for you.
- The authentication we exercised is the same **token → webhook → STS
  `GetCallerIdentity`** flow we decoded by hand earlier: IAM is the source of truth for
  *who* reaches the cluster; RBAC decides *what* they can do once in.

---

## One-line summary

**IAM Groups decide who gets in; Kubernetes RBAC decides what they can do — and mapping
roles (not users) makes granting or revoking access as simple as editing group
membership.**
