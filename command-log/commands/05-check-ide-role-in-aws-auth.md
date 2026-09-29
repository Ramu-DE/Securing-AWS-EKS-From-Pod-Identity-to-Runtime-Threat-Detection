# Command 05: Find the IDE's IAM role and check it against the `aws-auth` ConfigMap

```bash
# Block 1 — identify the IAM role attached to the IDE instance
IDE_ROLE_ARN=$(aws sts get-caller-identity --query Arn)
IDE_ROLE=$(echo $IDE_ROLE_ARN | cut -d'/' -f 2)
echo "$IDE_ROLE"

# Block 2 — check whether that role appears in the aws-auth ConfigMap
DOES_ROLE_EXISTS_IN_CONFIGMAP=$(kubectl get cm aws-auth -n kube-system -o yaml 2>/dev/null | grep $IDE_ROLE)
echo $DOES_ROLE_EXISTS_IN_CONFIGMAP

if [ -z "$DOES_ROLE_EXISTS_IN_CONFIGMAP" ]
then
      echo "$IDE_ROLE doesn't exist in aws-auth config map in kube-system namespace"
else
      echo "$IDE_ROLE exists in aws-auth config map in kube-system namespace"
fi
```

> Concept background lives in
> [`modules-docs/iam-groups-and-roles-aws-auth.md`](../../modules-docs/iam-groups-and-roles-aws-auth.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Identify the IAM role the IDE uses, then check whether that role is granted cluster access through the legacy `aws-auth` ConfigMap. |
| 2 | **What happens in Kubernetes** | A **read-only** query: `kubectl get cm aws-auth -n kube-system` reads (or fails to find) the `aws-auth` ConfigMap in the `kube-system` namespace. Nothing is modified. |
| 3 | **Which AWS service is called/used** | **AWS STS** (`sts:GetCallerIdentity`) to get the caller ARN, and **Amazon EKS** (via `kubectl` to the EKS API server) to read the ConfigMap. IAM is the underlying identity system being examined. |

---

## 1. In one sentence

First we find out **which IAM role our IDE is using**, then we check **whether that role
is granted cluster access via the legacy `aws-auth` ConfigMap**.

---

## 2. Background concepts (for beginners)

- **`aws sts get-caller-identity`** = asks AWS "who am I right now?" and returns your
  account, ARN, and UserId.
- **ARN (Amazon Resource Name)** = a unique ID for an AWS resource, e.g.
  `arn:aws:sts::ACCOUNT_ID:assumed-role/<role-name>/<session>`.
- **`cut -d'/' -f 2`** = split text on the `/` character and keep field 2 — a quick way to
  pull the role name out of the ARN.
- **`aws-auth` ConfigMap** = the legacy object mapping IAM roles/users to Kubernetes
  identities. If a role isn't listed there (and isn't granted via access entries), it
  can't use the cluster.
- **`[ -z "$VAR" ]`** = a test that is true when `$VAR` is **empty** (zero length). Used
  here to decide which message to print.

---

## 3. Line-by-line breakdown

### Block 1 — identify the IDE role
| Line | What it does |
|------|--------------|
| `IDE_ROLE_ARN=$(aws sts get-caller-identity --query Arn)` | Get the caller's ARN and store it. `--query Arn` picks just the ARN field. |
| `IDE_ROLE=$(echo $IDE_ROLE_ARN \| cut -d'/' -f 2)` | Split the ARN on `/` and keep the 2nd piece — the role name. |
| `echo "$IDE_ROLE"` | Print the role name. |

### Block 2 — check the ConfigMap
| Line | What it does |
|------|--------------|
| `kubectl get cm aws-auth -n kube-system -o yaml` | Fetch the `aws-auth` ConfigMap from the `kube-system` namespace as YAML. (`cm` = configmap.) |
| `2>/dev/null` | Silence errors (e.g. if the ConfigMap doesn't exist). |
| `\| grep $IDE_ROLE` | Search that YAML for our role name. |
| `if [ -z ... ]` | If the grep found nothing (empty), print "doesn't exist"; otherwise "exists". |

---

## 4. Why we run it in the workshop

- To discover the **cluster creator identity** (the IDE role) — the entity that got
  automatic `system:masters` / `cluster-admin` access.
- To inspect **how** that access is granted: via the legacy `aws-auth` ConfigMap, or (as
  on this Auto Mode cluster) via the modern **access entries** mechanism.

---

## 5. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, region `us-west-2`)

```
=== Block 1: identify IDE role ===
ARN: "arn:aws:sts::ACCOUNT_ID:assumed-role/vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe/i-0b028d229b5f3c736"
IDE_ROLE: vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe

=== Block 2: check aws-auth ConfigMap ===
grep result: (empty)
vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe doesn't exist in aws-auth config map in kube-system namespace
```

Exit status: `0`.

### Reading the result — this is an important teaching moment

The IDE role is **`vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe`**, matching
the expected `vscode-server-...-VSCodeInstanceRole-XXXX` pattern. This is the role that
created and authenticates to the `eks-auto` cluster.

The check reports the role **doesn't exist** in the `aws-auth` ConfigMap. We confirmed
*why* by querying the ConfigMap directly:

```bash
$ kubectl get cm aws-auth -n kube-system
Error from server (NotFound): configmaps "aws-auth" not found
```

**The `aws-auth` ConfigMap does not exist yet on this cluster.** That is expected and
consistent with how our Terraform built it:

- `eks-auto` is an **EKS Auto Mode** cluster created via the
  `terraform-aws-modules/eks` module with
  `enable_cluster_creator_admin_permissions = true`.
- That setting grants the creator admin rights through a modern **EKS access entry**, not
  through the legacy ConfigMap. So the creator has full `cluster-admin` access even
  though it appears nowhere in `aws-auth`.
- The cluster's `authentication_mode = "API_AND_CONFIG_MAP"` *permits* an `aws-auth`
  ConfigMap, but one is only created when you (or a later lab) actually add a mapping.

**Takeaway for beginners:** "not in `aws-auth`" does **not** mean "no access." On modern
EKS/Auto Mode, access is granted via access entries. The `aws-auth` ConfigMap is the
legacy path this module is about to demonstrate by having you *add* a mapping to it.

---

## 6. Handy related commands

```bash
aws sts get-caller-identity                         # Full identity (account, ARN, UserId)
kubectl get cm -n kube-system                       # List ConfigMaps in kube-system
kubectl get cm aws-auth -n kube-system -o yaml      # View the aws-auth ConfigMap (if it exists)
aws eks list-access-entries --cluster-name eks-auto # List modern access entries instead
```
