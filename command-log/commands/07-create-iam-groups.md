# Command 07: Create 3 IAM groups and attach assume-role policies

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# --- Pattern repeated for each group (k8sAdmin, k8sDev, k8sInteg) ---

# 1) Create the group if it doesn't exist (idempotent)
IAM_GROUP="k8sAdmin"
export IAM_GROUP_ARN=$(aws iam get-group --group-name $IAM_GROUP 2>/dev/null | jq -r '.Group.Arn')
if [ -z "$IAM_GROUP_ARN" ]; then
  IAM_GROUP_ARN=$(aws iam create-group --group-name $IAM_GROUP | jq -r '.Group.Arn')
  echo "IAM Group ${IAM_GROUP} created. IAM_GROUP_ARN=$IAM_GROUP_ARN"
else
  echo "IAM Group ${IAM_GROUP} already exist..."
fi

# 2) Attach an inline policy allowing members to assume the matching role
ADMIN_GROUP_POLICY=$(echo -n '{"Version":"2012-10-17","Statement":[{"Sid":"AllowAssumeOrganizationAccountRole","Effect":"Allow","Action":"sts:AssumeRole","Resource":"arn:aws:iam::'; echo -n "$ACCOUNT_ID"; echo -n ':role/k8sAdmin"}]}')
aws iam put-group-policy --group-name k8sAdmin --policy-name k8sAdmin-policy --policy-document "$ADMIN_GROUP_POLICY"

# ... same for k8sDev (assume role k8sDev) and k8sInteg (assume role k8sInteg) ...

aws iam list-groups   # confirm all 3 groups exist
```

> Concept background lives in
> [`modules-docs/kubernetes-authentication-rbac.md`](../../modules-docs/kubernetes-authentication-rbac.md).
> This pairs with [command 06](./06-create-iam-roles.md) which created the roles.

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Create 3 IAM groups (`k8sAdmin`, `k8sDev`, `k8sInteg`) and give each an inline policy permitting members to **assume the matching IAM role** from command 06. |
| 2 | **What happens in Kubernetes** | **Nothing yet.** These are pure AWS/IAM objects. They only translate to cluster access once the roles are mapped into Kubernetes RBAC (a later step). |
| 3 | **Which AWS service is called/used** | **AWS IAM** (`iam:GetGroup`, `iam:CreateGroup`, `iam:PutGroupPolicy`, `iam:ListGroups`) and **AWS STS** (`sts:GetCallerIdentity` for the account ID). The policies *grant* `sts:AssumeRole`, but no assume happens here. |

---

## 1. In one sentence

Create three IAM groups so that **group membership** decides which cluster-access role a
user can assume — the clean, scalable way to hand out (and revoke) EKS access.

---

## 2. Why groups? (the whole point)

We want different IAM **users** added to specific IAM **groups** so they get different
rights in the Kubernetes cluster:

| Group | What its members get |
|-------|----------------------|
| `k8sAdmin` | Admin rights on the whole cluster. |
| `k8sDev` | Full access only in the **development** namespace. |
| `k8sInteg` | Access to the **integration** namespace. |

Instead of editing access per-user per-cluster (tedious, error-prone), you just add or
remove a user from a group. The group's policy lets its members **assume** the matching
role; the role is then mapped to Kubernetes RBAC for the actual in-cluster permissions.

> `k8sDev` / `k8sInteg` members only truly have access to the namespaces where we later
> define Kubernetes RBAC for their associated role.

---

## 3. Background concepts (for beginners)

- **IAM group** = a collection of IAM users. Policies attached to the group apply to all
  its members. Groups can't be assumed — they're just a way to manage users in bulk.
- **Inline policy** (via `put-group-policy`) = a policy embedded directly in the group
  (as opposed to a standalone managed policy). Here it grants exactly one thing:
  `sts:AssumeRole` on one specific role ARN.
- **The link:** group policy grants `sts:AssumeRole` → user assumes the role → the role is
  mapped to Kubernetes RBAC → user gets cluster permissions.

---

## 4. Why the account ID must be set

Each group policy references `arn:aws:iam::$ACCOUNT_ID:role/<role>`. If `$ACCOUNT_ID` is
**empty**, the policy becomes malformed (`arn:aws:iam:::role/...`) and later
`sts:AssumeRole` calls fail with **AccessDenied**. That's why the module re-exports
`ACCOUNT_ID` at the top — safe to re-run in any new terminal.

---

## 5. Line-by-line breakdown (per group)

| Piece | What it does |
|-------|--------------|
| `aws iam get-group --group-name $IAM_GROUP` | Check if the group already exists (ARN empty if not). |
| `aws iam create-group --group-name $IAM_GROUP` | Create the group (only when missing — idempotent). |
| `put-group-policy --policy-name <group>-policy --policy-document "$POLICY"` | Attach the inline policy allowing `sts:AssumeRole` on the matching role. |
| `aws iam list-groups` | List all groups to confirm the three exist. |

---

## 6. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, account `ACCOUNT_ID`)

```
ACCOUNT_ID=ACCOUNT_ID
IAM Group k8sAdmin created. IAM_GROUP_ARN=arn:aws:iam::ACCOUNT_ID:group/k8sAdmin
  -> attached k8sAdmin-policy (assume role k8sAdmin)
IAM Group k8sDev created. IAM_GROUP_ARN=arn:aws:iam::ACCOUNT_ID:group/k8sDev
  -> attached k8sDev-policy (assume role k8sDev)
IAM Group k8sInteg created. IAM_GROUP_ARN=arn:aws:iam::ACCOUNT_ID:group/k8sInteg
  -> attached k8sInteg-policy (assume role k8sInteg)

=== aws iam list-groups (k8s* only) ===
k8sAdmin   arn:aws:iam::ACCOUNT_ID:group/k8sAdmin
k8sDev     arn:aws:iam::ACCOUNT_ID:group/k8sDev
k8sInteg   arn:aws:iam::ACCOUNT_ID:group/k8sInteg
```
Exit status: `0`. All three groups newly created and policies attached.

**Verification** of the `k8sAdmin` group's inline policy:

```jsonc
// aws iam get-group-policy --group-name k8sAdmin --policy-name k8sAdmin-policy
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAssumeOrganizationAccountRole",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::ACCOUNT_ID:role/k8sAdmin"
    }
  ]
}
```

The policy is well-formed (account ID correctly substituted) and scopes the group to
assuming **only** its matching role — exactly as intended.

---

## 7. Handy related commands

```bash
aws iam list-groups                                             # All groups
aws iam list-group-policies --group-name k8sAdmin               # Inline policy names on a group
aws iam get-group-policy --group-name k8sAdmin --policy-name k8sAdmin-policy   # View a policy
aws iam get-group --group-name k8sAdmin                         # Group details + members
```
