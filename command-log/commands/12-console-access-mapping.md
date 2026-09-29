# Command 12: Grant AWS Console access to the EKS cluster (optional)

```bash
# 1) Derive your IAM role ARN from the current caller identity
rolearn=$(aws sts get-caller-identity --query Arn --output text \
  | sed 's|sts|iam|; s|assumed-role|role|; s|/[^/]*$||')
echo Role ARN: ${rolearn}

# 2) Map that role into the cluster as a cluster admin (guarded against duplicates)
if eksctl get iamidentitymapping --cluster eks-auto --arn ${rolearn} >/dev/null 2>&1; then
  echo "console role ${rolearn} is already mapped, skipping"
else
  eksctl create iamidentitymapping --cluster eks-auto --arn ${rolearn} \
    --group system:masters --username admin
fi

# 3) Verify the mapping landed in aws-auth
kubectl describe configmap -n kube-system aws-auth
```

> Concept background lives in
> [`modules-docs/iam-groups-and-roles-aws-auth.md`](../../modules-docs/iam-groups-and-roles-aws-auth.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | (Optional) Grant your **AWS Console** identity permission to view Kubernetes objects (Deployments, Pods, Nodes) in the EKS console, by mapping your IAM role into the cluster as admin. |
| 2 | **What happens in Kubernetes** | Adds a **4th `mapRoles` entry** to the `aws-auth` ConfigMap: your IDE role → K8s user `admin` in `system:masters` (full admin). |
| 3 | **Which AWS service is called/used** | **AWS STS** (`sts:GetCallerIdentity` to derive the ARN), **Amazon EKS** (API server via `eksctl`/`kubectl` to edit `aws-auth`), **IAM** (the role being mapped). Enables the **EKS console** view afterward. |

---

## 1. In one sentence

Map the identity you use in the AWS Console into the cluster's `aws-auth` ConfigMap so the
EKS console can show you Kubernetes resources, not just AWS-level cluster config.

---

## 2. Why this is needed

The EKS console shows two kinds of information:
- **AWS-level config** (endpoint, version, networking) — visible with normal AWS
  permissions.
- **Kubernetes objects** (Deployments, Pods, Nodes) — require the console IAM identity to
  be **granted permission inside the cluster** (via `aws-auth` or access entries).

By default only the **cluster creator** has in-cluster permissions. Here the cluster was
created by the **IDE instance's IAM role**, so if your console session uses a *different*
identity you must add it. (In this environment they're the same role, which is itself
instructive — see the execution note.)

---

## 3. Background concepts (for beginners)

- **The `sed` transform** rewrites the *assumed-role* ARN into the underlying *role* ARN:
  | Substitution | Effect |
  |--------------|--------|
  | `s\|sts\|iam\|` | `arn:aws:sts:...` → `arn:aws:iam:...` |
  | `s\|assumed-role\|role\|` | `.../assumed-role/NAME/session` → `.../role/NAME/session` |
  | `s\|/[^/]*$\|\|` | strips the trailing `/session` part |
  Net result: the stable **role ARN** (what `aws-auth` needs), derived from a temporary
  session ARN — works regardless of environment.
- **`--group system:masters`** = grants full cluster-admin (workshop convenience).
- **Guard:** `eksctl create` doesn't dedupe, so we check with `eksctl get` first.

> Permissions *can* be restricted and granular; because this is a workshop cluster we add
> the console credential as **administrator** for simplicity.

---

## 4. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`). Account ID masked below.

**Derived role ARN:**
```
Role ARN: arn:aws:iam::ACCOUNT_ID:role/vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe
```

**Mapping created:**
```
adding identity "arn:aws:iam::ACCOUNT_ID:role/vscode-server-...-VSCodeInstanceRole-Kj5ncTeGjYFe" to auth ConfigMap
```
Exit status: `0`.

**Verification — `aws-auth` now has 4 role mappings:**
```yaml
mapRoles:
- rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sDev        username: dev-user
- rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sInteg      username: integ-user
- groups: [system:masters]
  rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sAdmin       username: admin
- groups: [system:masters]
  rolearn: arn:aws:iam::ACCOUNT_ID:role/vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe
  username: admin
mapUsers: |
  []
```

### This closes the loop from command 05

Back in [command 05](./05-check-ide-role-in-aws-auth.md), the IDE role
`vscode-server-...-VSCodeInstanceRole-Kj5ncTeGjYFe` **did not appear** in `aws-auth` (the
ConfigMap didn't even exist then; the role had admin via an **EKS access entry**). This
command explicitly adds that same IDE role to `aws-auth` as `admin`/`system:masters` — so
it now has admin access through **both** mechanisms (access entry *and* ConfigMap). That's
a clean demonstration that the two mechanisms coexist under `API_AND_CONFIG_MAP`.

---

## 5. Result

You can now open the **Amazon EKS console** and view Kubernetes objects (Deployments,
Pods, Nodes) for the `eks-auto` cluster, in addition to the AWS-level configuration.

---

## 6. Handy related commands

```bash
eksctl get iamidentitymapping --cluster eks-auto           # List all mapped identities
kubectl describe configmap aws-auth -n kube-system          # Human-readable aws-auth
aws eks list-access-entries --cluster-name eks-auto         # Compare: modern access entries
```
