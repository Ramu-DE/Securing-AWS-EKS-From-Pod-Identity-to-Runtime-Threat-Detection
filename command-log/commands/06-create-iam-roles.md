# Command 06: Create 3 least-privileged IAM roles (`k8sAdmin`, `k8sDev`, `k8sInteg`)

```bash
# Ensure ACCOUNT_ID is set (trust policy references it)
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "ACCOUNT_ID=$ACCOUNT_ID"

# Trust policy: allow the account root to assume the role
POLICY=$(echo -n '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"AWS":"arn:aws:iam::'; echo -n "$ACCOUNT_ID"; echo -n ':root"},"Action":"sts:AssumeRole","Condition":{}}]}')

# For each role: look it up; create it only if it doesn't already exist (idempotent)
export IAM_ROLE="k8sAdmin"
export ROLE_DESCRIPTION="Kubernetes administrator role (for AWS IAM Authenticator for Kubernetes)."
export IAM_ROLE_ARN=$(aws iam get-role --role-name $IAM_ROLE 2>/dev/null | jq -r '.Role.Arn')
if [ -z "$IAM_ROLE_ARN" ]; then
  IAM_ROLE_ARN=$(aws iam create-role --role-name $IAM_ROLE --description "$ROLE_DESCRIPTION" \
    --assume-role-policy-document "$POLICY" --output text --query 'Role.Arn')
  echo "IAM Role ${IAM_ROLE} created. IAM_ROLE_ARN=$IAM_ROLE_ARN"
else
  echo "IAM Role ${IAM_ROLE} already exist..."
fi
# ... repeated for k8sDev and k8sInteg (same block, different name/description) ...
```

> Concept background lives in
> [`modules-docs/kubernetes-authentication-rbac.md`](../../modules-docs/kubernetes-authentication-rbac.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Create three **authentication-only** IAM roles — `k8sAdmin`, `k8sDev`, `k8sInteg` — that will later be mapped to Kubernetes RBAC to control who can do what in the cluster. |
| 2 | **What happens in Kubernetes** | **Nothing yet.** These are pure AWS/IAM objects. They only affect Kubernetes *later*, once we map them into RBAC (via `aws-auth` or access entries). |
| 3 | **Which AWS service is called/used** | **AWS IAM** (`iam:GetRole`, `iam:CreateRole`) to create the roles, and **AWS STS** (`sts:GetCallerIdentity`) to fetch the account ID. |

---

## 1. In one sentence

Create three IAM roles that carry **no AWS permissions at all** — their only job is to be
**assumable identities** we can later tie to Kubernetes RBAC roles.

---

## 2. The three roles and their intended cluster access

| Role | Intended EKS access (granted later via RBAC) |
|------|----------------------------------------------|
| `k8sAdmin` | Admin rights across the whole cluster. |
| `k8sDev` | Access to the **developers** namespace only. |
| `k8sInteg` | Access to the **integration** namespace only. |

> "Least privileged" = each role is scoped to only what its users need. The scoping is
> enforced by the **Kubernetes RBAC** we bind later, plus the **IAM group policies**
> created in the next step.

---

## 3. Background concepts (for beginners)

- **IAM role** = an identity you can *assume* (temporarily become) to get a set of
  permissions. Unlike a user, a role has no long-term password/keys.
- **Trust policy (assume-role policy)** = defines **WHO is allowed to assume the role**.
  Separate from permission policies, which define **what the role can do**.
- **`arn:aws:iam::<ACCOUNT_ID>:root`** = shorthand meaning "the entire AWS account." A
  trust policy naming `:root` lets *any* principal in the account (that also has
  `sts:AssumeRole` permission) assume the role.
- **Idempotent** = safe to run repeatedly. The `if [ -z "$IAM_ROLE_ARN" ]` check means "if
  the role doesn't already exist, create it" — so re-running won't error or duplicate.

---

## 4. Line-by-line breakdown

| Piece | What it does |
|-------|--------------|
| `export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)` | Fetch the 12-digit account ID and export it. |
| `POLICY=$(echo -n '{...}')` | Build the trust-policy JSON string, splicing in the account ID for the `:root` principal. |
| `aws iam get-role --role-name $IAM_ROLE 2>/dev/null \| jq -r '.Role.Arn'` | Try to fetch the role's ARN; empty if the role doesn't exist. |
| `if [ -z "$IAM_ROLE_ARN" ]` | If the ARN is empty (role missing)... |
| `aws iam create-role --role-name ... --assume-role-policy-document "$POLICY"` | ...create the role with that trust policy and description. |
| `else echo "... already exist..."` | Otherwise skip creation (idempotent). |

---

## 5. Why these roles have NO permissions

Because these roles are used **only to authenticate within the EKS cluster**, they don't
need any AWS permissions. We use them purely to let certain **IAM groups** assume them,
which then grants cluster access via RBAC. In the IAM console you'd see the `k8sAdmin`
role with **zero** permission policies attached and a trust policy allowing `:root`.

---

## 6. ⚠️ Security note — don't ship a `:root` trust policy

The trust policy uses `Principal: { "AWS": "arn:aws:iam::ACCOUNT_ID:root" }`. In a
**security lab** this keeps setup simple, but it means **every** principal in the account
that also holds `sts:AssumeRole` can assume `k8sAdmin`/`k8sDev`/`k8sInteg`. Only the IAM
**group policies** created in the next step scope who actually can.

**In production:** scope the trust policy to the specific principals or exact group ARNs
instead of `:root`, so "who may assume this cluster-access role" is enforced in one place
rather than relying on group-policy hygiene alone. **Never leave `:root` on a role that
maps to `system:masters`.**

---

## 7. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, account `ACCOUNT_ID`)

```
ACCOUNT_ID=ACCOUNT_ID
IAM Role k8sAdmin created. IAM_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/k8sAdmin
IAM Role k8sDev created. IAM_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/k8sDev
IAM Role k8sInteg created. IAM_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/k8sInteg
```
Exit status: `0`. All three roles were newly created (none existed before).

**Verification** — confirmed the trust policy and the absence of permissions on `k8sAdmin`:

```jsonc
// aws iam get-role --role-name k8sAdmin --query 'Role.AssumeRolePolicyDocument'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
      "Action": "sts:AssumeRole",
      "Condition": {}
    }
  ]
}
```
```
attached managed policies : []      # none — as intended
inline policies           : []      # none — as intended
```

This matches the theory exactly: the role trusts the account root and carries **no**
permissions; its power will come entirely from the Kubernetes RBAC we bind next.

---

## 8. Handy related commands

```bash
aws iam get-role --role-name k8sAdmin                        # Full role detail incl. trust policy
aws iam list-attached-role-policies --role-name k8sAdmin     # Managed policies (expect none)
aws iam list-role-policies --role-name k8sAdmin              # Inline policies (expect none)
aws iam delete-role --role-name k8sAdmin                     # Cleanup (only after removing bindings)
```
