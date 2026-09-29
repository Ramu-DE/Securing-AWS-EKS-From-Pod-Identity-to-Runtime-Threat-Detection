# Command 21: Create access entries and associate access policies (3 personas)

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export CL=eks-auto

# (a) IAM roles (auth-only, :root trust) + IAM groups with assume-role inline policies
#     k8sClusterAdmin / k8sTeamADev / k8sTeamATest   (same pattern as commands 06/07)

# (b) namespace for team A
kubectl create namespace team-a --dry-run=client -o yaml | kubectl apply -f -

# (c) one access ENTRY per role (links the IAM role as a cluster identity)
aws eks create-access-entry --cluster-name $CL --principal-arn arn:aws:iam::$ACCOUNT_ID:role/<role>

# (d) associate an EKS access POLICY with an access SCOPE
aws eks associate-access-policy --cluster-name $CL --principal-arn arn:aws:iam::$ACCOUNT_ID:role/k8sClusterAdmin \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy --access-scope '{"type":"cluster"}'
aws eks associate-access-policy --cluster-name $CL --principal-arn arn:aws:iam::$ACCOUNT_ID:role/k8sTeamADev \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy --access-scope '{"type":"namespace","namespaces":["team-a"]}'
aws eks associate-access-policy --cluster-name $CL --principal-arn arn:aws:iam::$ACCOUNT_ID:role/k8sTeamATest \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy --access-scope '{"type":"namespace","namespaces":["team-a"]}'
```

> Concept + plan: [`modules-docs/access-entries-persona-plan.md`](../../modules-docs/access-entries-persona-plan.md),
> [`modules-docs/eks-access-management-controls.md`](../../modules-docs/eks-access-management-controls.md).
> This is the **modern** rebuild of the legacy `aws-auth` mapping from
> [command 10](./10-configure-aws-auth-configmap.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Grant three personas scoped cluster access **the modern way** — access entries + EKS access policies — instead of `aws-auth` + hand-written RBAC. ClusterAdmin = cluster-wide; TeamADev = admin on `team-a`; TeamATest = view on `team-a`. |
| 2 | **What happens in Kubernetes** | Creates namespace `team-a`. The access entries/policies make the EKS authorizer grant each IAM role the mapped Kubernetes permissions (cluster-admin / admin / view) — **no Role/RoleBinding authored by hand**. |
| 3 | **Which AWS service is called/used** | **AWS IAM** (`create-role`, `create-group`, `put-group-policy`), **Amazon EKS** (`create-access-entry`, `associate-access-policy`, and the API server for the namespace). Access policies are **EKS** entities. |

---

## 1. In one sentence

Wire `k8sClusterAdmin`/`k8sTeamADev`/`k8sTeamATest` into the cluster via **access entries**
and **EKS-managed access policies**, scoping the two team roles to the `team-a` namespace.

---

## 2. The persona → policy → scope mapping

| IAM role (group) | EKS access policy | Access scope | Effective permission |
|------------------|-------------------|--------------|----------------------|
| `k8sClusterAdmin` | `AmazonEKSClusterAdminPolicy` | `cluster` | Full cluster-admin everywhere |
| `k8sTeamADev` | `AmazonEKSAdminPolicy` | `namespace: [team-a]` | Admin **only** in `team-a` |
| `k8sTeamATest` | `AmazonEKSViewPolicy` | `namespace: [team-a]` | Read-only **only** in `team-a` |

---

## 3. Why this is simpler than aws-auth (commands 06–11)

- **No hand-written Role/RoleBinding.** The **access policy** (`admin`/`view`/`cluster-admin`)
  already encodes the Kubernetes permissions.
- **No `system:masters`.** `AmazonEKSClusterAdminPolicy` provides cluster-admin cleanly.
- **Namespace scoping is a parameter** (`--access-scope`), not a separate RBAC object.
- **Managed from outside the cluster** via the EKS API — the AWS-recommended approach for
  new clusters and EKS Auto Mode.

---

## 4. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`). Account masked as `ACCOUNT_ID`.

### 4a. Roles + groups created
```
Role k8sClusterAdmin created: arn:aws:iam::ACCOUNT_ID:role/k8sClusterAdmin
Role k8sTeamADev     created: arn:aws:iam::ACCOUNT_ID:role/k8sTeamADev
Role k8sTeamATest    created: arn:aws:iam::ACCOUNT_ID:role/k8sTeamATest
Group k8sClusterAdmin/k8sTeamADev/k8sTeamATest created (+ <group>-policy: assume matching role)
```
(Each role is **auth-only** with a `:root` trust policy — same least-privilege pattern as
[command 06](./06-create-iam-roles.md). In production, scope the trust policy to the group.)

### 4b. Namespace + access entries + associations
```
namespace/team-a created
access entry created for k8sClusterAdmin
access entry created for k8sTeamADev
access entry created for k8sTeamATest
  -> k8sClusterAdmin associated AmazonEKSClusterAdminPolicy scope={"type":"cluster"}
  -> k8sTeamADev     associated AmazonEKSAdminPolicy        scope={"type":"namespace","namespaces":["team-a"]}
  -> k8sTeamATest    associated AmazonEKSViewPolicy         scope={"type":"namespace","namespaces":["team-a"]}
```

### 4c. Verification — associated policies per principal
```json
// k8sClusterAdmin
[{ "policy": ".../AmazonEKSClusterAdminPolicy", "scope": "cluster",   "ns": [] }]
// k8sTeamADev
[{ "policy": ".../AmazonEKSAdminPolicy",        "scope": "namespace", "ns": ["team-a"] }]
// k8sTeamATest
[{ "policy": ".../AmazonEKSViewPolicy",         "scope": "namespace", "ns": ["team-a"] }]
```
Each persona has exactly the intended policy and scope. ✅

---

## 5. How the EKS authorizer uses this

When one of these roles calls the cluster, the request flows: upstream RBAC (pass) →
**EKS access-entry authorizer**, which sees the principal's **access entry** and its
**associated access policy + scope**, and grants the corresponding Kubernetes permissions
(cluster-admin / admin@team-a / view@team-a). See the authorizer chain in
[`eks-access-management-controls.md`](../../modules-docs/eks-access-management-controls.md).

---

## 6. Handy related commands

```bash
aws eks list-access-entries --cluster-name eks-auto
aws eks describe-access-entry --cluster-name eks-auto --principal-arn <ARN>
aws eks list-associated-access-policies --cluster-name eks-auto --principal-arn <ARN>
# Cleanup:
aws eks disassociate-access-policy --cluster-name eks-auto --principal-arn <ARN> --policy-arn <policy>
aws eks delete-access-entry --cluster-name eks-auto --principal-arn <ARN>
```
