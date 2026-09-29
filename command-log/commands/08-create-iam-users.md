# Command 08: Create 3 IAM users, add them to groups, and mint access keys

```bash
# 1) Create the 3 test users (idempotent)
IAM_USERS=("PaulAdmin" "JeanDev" "PierreInteg")
for IAM_USER in ${IAM_USERS[@]}; do
    export IAM_USER_ARN=$(aws iam get-user --user-name $IAM_USER 2>/dev/null | jq -r '.User.Arn')
    if [ -z "$IAM_USER_ARN" ]; then
        IAM_USER_ARN=$(aws iam create-user --user-name $IAM_USER | jq -r '.User.Arn')
        echo "IAM User ${IAM_USER} created. IAM_USER_ARN=$IAM_USER_ARN"
    else
        echo "IAM User ${IAM_USER} already exist..."
    fi
done

# 2) Add each user to its matching group
aws iam add-user-to-group --group-name k8sAdmin --user-name PaulAdmin
aws iam add-user-to-group --group-name k8sDev   --user-name JeanDev
aws iam add-user-to-group --group-name k8sInteg --user-name PierreInteg

# 3) Verify membership
aws iam get-group --group-name k8sAdmin
aws iam get-group --group-name k8sDev
aws iam get-group --group-name k8sInteg

# 4) Mint access keys (guarded: IAM allows max 2 keys/user; reuse saved file if present)
for U in PaulAdmin JeanDev PierreInteg; do
  if [ -s /tmp/$U.json ] && jq -e '.AccessKey.AccessKeyId' /tmp/$U.json >/dev/null 2>&1; then
    echo "$U: reusing existing key file /tmp/$U.json"
  else
    aws iam create-access-key --user-name $U > /tmp/$U.json
    echo "$U: access key created (saved to /tmp/$U.json)"
  fi
done
```

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Create 3 test users (one per group), place each in its group, and generate access keys so we can later log in *as* each user and test their scoped cluster access. |
| 2 | **What happens in Kubernetes** | **Nothing yet.** Pure IAM setup. These users gain cluster access only after their roles are mapped into Kubernetes RBAC (later step). |
| 3 | **Which AWS service is called/used** | **AWS IAM** only: `iam:GetUser`, `iam:CreateUser`, `iam:AddUserToGroup`, `iam:GetGroup`, `iam:CreateAccessKey`. |

---

## 1. In one sentence

Create three fake users — **PaulAdmin**, **JeanDev**, **PierreInteg** — put each in the
matching group, and give each long-term credentials so we can impersonate them to test
the scoped access model end to end.

---

## 2. The mapping we're building

| User | Group | Will be able to assume role | Effective cluster access (later) |
|------|-------|-----------------------------|----------------------------------|
| `PaulAdmin` | `k8sAdmin` | `k8sAdmin` | Cluster admin |
| `JeanDev` | `k8sDev` | `k8sDev` | `development` namespace |
| `PierreInteg` | `k8sInteg` | `k8sInteg` | `integration` namespace |

This completes the **user → group → role** chain. The final link (**role → Kubernetes
RBAC**) comes next.

---

## 3. Background concepts (for beginners)

- **IAM user** = a long-lived identity for a person or app, with its own credentials.
- **Access key** = a long-term credential pair (**Access Key ID** + **Secret Access
  Key**) used to authenticate to AWS programmatically (CLI/SDK). IAM allows a **maximum of
  2 access keys per user**.
- **`add-user-to-group`** = makes the user a member of the group, so the group's policies
  (here: permission to assume a role) apply to that user.

---

## 4. Why the access-key step is "guarded"

A plain `aws iam create-access-key` on every run would eventually fail with
**`LimitExceeded`** (max 2 keys/user). The loop first checks whether a valid key file
already exists in `/tmp/$U.json`:
- **exists & valid** → reuse it (print a message, mint nothing new).
- **missing/invalid** → create a new key and save the JSON.

This makes the step **idempotent** and re-runnable.

---

## 5. ⚠️ Security note (important)

> For the sake of simplicity, this chapter **saves credentials to files** (`/tmp/*.json`)
> to toggle between users. **Never do this in production**, or with credentials that have
> privileged access. Storing credentials on the filesystem is **not** a security best
> practice.

In this log, the **Secret Access Keys are never printed or committed**. Only the
(less-sensitive) Access Key **IDs** are shown, and even those are partially redacted.
These are throwaway lab users, but the secret half of any key must still be treated as a
live credential.

---

## 6. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, account `ACCOUNT_ID`)

```
=== Create users ===
IAM User PaulAdmin created.   ARN=arn:aws:iam::ACCOUNT_ID:user/PaulAdmin
IAM User JeanDev created.     ARN=arn:aws:iam::ACCOUNT_ID:user/JeanDev
IAM User PierreInteg created. ARN=arn:aws:iam::ACCOUNT_ID:user/PierreInteg

=== Add users to groups ===
PaulAdmin   -> k8sAdmin
JeanDev     -> k8sDev
PierreInteg -> k8sInteg

=== Verify group membership ===
k8sAdmin members: PaulAdmin
k8sDev members:   JeanDev
k8sInteg members: PierreInteg

=== Create access keys (guarded) ===
PaulAdmin:   access key created (saved to /tmp/PaulAdmin.json),   AccessKeyId=AKIA...CF7R
JeanDev:     access key created (saved to /tmp/JeanDev.json),     AccessKeyId=AKIA...56VO
PierreInteg: access key created (saved to /tmp/PierreInteg.json), AccessKeyId=AKIA...W6FL
```
Exit status: `0`. All three users created, correctly placed in their single matching
group, and issued one access key each (secret halves redacted here).

---

## 7. Recap of what now exists

- **PaulAdmin** is in the `k8sAdmin` group → can assume the `k8sAdmin` role.
- **JeanDev** is in the `k8sDev` group → can assume the `k8sDev` role.
- **PierreInteg** is in the `k8sInteg` group → can assume the `k8sInteg` role.

Next we map these roles into the cluster's Kubernetes RBAC so the access actually takes
effect.

---

## 8. Handy related commands

```bash
aws iam get-group --group-name k8sAdmin              # See members of a group
aws iam list-access-keys --user-name PaulAdmin       # List a user's access key IDs (not secrets)
aws iam list-groups-for-user --user-name PaulAdmin   # Which groups is a user in?
# Cleanup later:
aws iam remove-user-from-group --group-name k8sAdmin --user-name PaulAdmin
aws iam delete-access-key --user-name PaulAdmin --access-key-id <ID>
aws iam delete-user --user-name PaulAdmin
```
