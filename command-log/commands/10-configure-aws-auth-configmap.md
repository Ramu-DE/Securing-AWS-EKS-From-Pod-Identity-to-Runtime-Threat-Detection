# Command 10: Map IAM roles into the cluster via the `aws-auth` ConfigMap

```bash
# 0) Confirm the cluster still honors the ConfigMap (must contain CONFIG_MAP)
aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode --output text

# 1) Add each IAM role -> Kubernetes username mapping (guarded against duplicates)
add_mapping () {  # $1=role  $2=username  [$3=--group group]
  if eksctl get iamidentitymapping --cluster eks-auto --arn arn:aws:iam::${ACCOUNT_ID}:role/$1 >/dev/null 2>&1; then
    echo "mapping for $1 already present, skipping"
  else
    eksctl create iamidentitymapping --cluster eks-auto --arn arn:aws:iam::${ACCOUNT_ID}:role/$1 --username $2 $3
  fi
}
add_mapping k8sDev   dev-user
add_mapping k8sInteg integ-user
add_mapping k8sAdmin admin "--group system:masters"

# 2) Inspect the result
kubectl get cm -n kube-system aws-auth -o yaml
eksctl get iamidentitymapping --cluster eks-auto
```

> Concept background lives in
> [`modules-docs/iam-groups-and-roles-aws-auth.md`](../../modules-docs/iam-groups-and-roles-aws-auth.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Map each IAM role to a Kubernetes username in the `aws-auth` ConfigMap, so assuming an IAM role logs you in as the matching K8s user with its RBAC rights. This is the **final link** in the access chain. |
| 2 | **What happens in Kubernetes** | Creates/updates the **`aws-auth` ConfigMap** in `kube-system` with three `mapRoles` entries. `k8sAdmin`→`admin` (in `system:masters`), `k8sDev`→`dev-user`, `k8sInteg`→`integ-user`. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** — `eks:DescribeCluster` to check auth mode, and the EKS API server (via `eksctl`/`kubectl`) to edit the ConfigMap. The mapped *targets* are **IAM** roles. |

---

## 1. In one sentence

Tell the cluster "when someone shows up having assumed IAM role `k8sDev`, treat them as
Kubernetes user `dev-user`" — which activates all the RBAC we built in command 09.

---

## 2. Why map roles (not users) — the whole advantage

Mapping the **IAM role** (rather than individual IAM users) means you **never edit the
ConfigMap to add/remove people.** To grant or revoke a person's access you just add or
remove them from the **IAM group** (command 07/08); the group lets them assume the role,
and the role is already mapped here. One ConfigMap entry serves an entire team.

---

## 3. ⚠️ Pre-flight check: is the ConfigMap path even active?

```bash
aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode --output text
```
The output **must contain `CONFIG_MAP`** (ours returned `API_AND_CONFIG_MAP`).

- If it returns **`API`** only, the ConfigMap path is **disabled** — the mappings would
  "succeed" but have **no effect**. Switching to API-only is **one-way**. In that case you
  must use **EKS access entries** instead.

---

## 4. Background concepts (for beginners)

- **`aws-auth` ConfigMap** = the legacy object in `kube-system` that maps AWS IAM
  identities to Kubernetes identities. `mapRoles` = role mappings; `mapUsers` = user
  mappings.
- **`eksctl create iamidentitymapping`** = a helper that safely edits `aws-auth` for you
  (instead of hand-editing YAML).
- **`--username`** = the Kubernetes username the role becomes (must match the RBAC
  subjects from command 09: `dev-user`, `integ-user`).
- **`--group system:masters`** = also add the mapped user to the built-in super-admin
  group. Used only for `k8sAdmin` → `admin`.
- **Dedupe guard:** `eksctl create` does **not** deduplicate — re-running would append a
  second, shadowing entry for the same ARN. The `add_mapping` wrapper checks first with
  `eksctl get` and skips if already present (idempotent).

---

## 5. The three mappings

| IAM role | K8s username | K8s group | Effective access |
|----------|--------------|-----------|------------------|
| `k8sAdmin` | `admin` | `system:masters` | **Full cluster admin** |
| `k8sDev` | `dev-user` | (none) | `dev-role` in `development` ns (command 09) |
| `k8sInteg` | `integ-user` | (none) | `integ-role` in `integration` ns (command 09) |

> **Note:** adding `admin` to `system:masters` is for example purposes. It is highly
> recommended **not** to add any user to `system:masters` unless necessary.

---

## 6. No node role here (EKS Auto Mode specifics)

On a traditional cluster, `aws-auth` also contains a `system:bootstrappers/system:nodes`
entry for the node instance role. On **EKS Auto Mode** the data-plane nodes are
AWS-managed and authorized through **EKS access entries**, not an `aws-auth` node mapping —
so you'll see **only** the role mappings we added, no node role. (On Auto Mode, access
entries are actually the recommended approach; this module uses `aws-auth` purely to
illustrate the ConfigMap mechanism, which stays supported while auth mode includes
`CONFIG_MAP`.)

---

## 7. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, account `ACCOUNT_ID`)

**Pre-flight:** `authenticationMode` returned **`API_AND_CONFIG_MAP`** ✓ (ConfigMap
honored) and `eksctl` version `0.230.0` is present.

**Mapping creation:**
```
adding identity "arn:aws:iam::ACCOUNT_ID:role/k8sDev"    -> dev-user
adding identity "arn:aws:iam::ACCOUNT_ID:role/k8sInteg"  -> integ-user
adding identity "arn:aws:iam::ACCOUNT_ID:role/k8sAdmin"  -> admin --group system:masters
```
Exit status: `0`.

**Resulting `aws-auth` ConfigMap** (account ID masked):
```yaml
apiVersion: v1
data:
  mapRoles: |
    - rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sDev
      username: dev-user
    - rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sInteg
      username: integ-user
    - groups:
      - system:masters
      rolearn: arn:aws:iam::ACCOUNT_ID:role/k8sAdmin
      username: admin
  mapUsers: |
    []
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
```

**`eksctl get iamidentitymapping`:**
```
ARN                                       USERNAME     GROUPS
arn:aws:iam::ACCOUNT_ID:role/k8sAdmin     admin        system:masters
arn:aws:iam::ACCOUNT_ID:role/k8sDev       dev-user
arn:aws:iam::ACCOUNT_ID:role/k8sInteg     integ-user
```

### Notable: the ConfigMap now exists

Back in [command 05](./05-check-ide-role-in-aws-auth.md) the `aws-auth` ConfigMap did
**not exist** at all (Auto Mode granted the creator via access entries). This command
**created it** — its `creationTimestamp` is `2026-09-29T03:11:53Z`, the moment the first
mapping was added. That's a clean before/after demonstration of the legacy mechanism.

---

## 8. What we've built so far (full picture)

- `k8sAdmin` role → `admin` user in `system:masters` → **full admin** on the cluster.
- `k8sDev` role → `dev-user` → `dev-role` in the `development` namespace.
- `k8sInteg` role → `integ-user` → `integ-role` in the `integration` namespace.

The complete chain is now live:
```
IAM User → IAM Group (assume-role policy) → IAM Role → [aws-auth map] → K8s user → Role/RoleBinding → namespace access
```

---

## 9. Handy related commands

```bash
eksctl get iamidentitymapping --cluster eks-auto              # List all mappings
kubectl get cm aws-auth -n kube-system -o yaml               # Raw ConfigMap
eksctl delete iamidentitymapping --cluster eks-auto --arn <ARN>   # Remove a mapping
aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode   # Auth mode
```
