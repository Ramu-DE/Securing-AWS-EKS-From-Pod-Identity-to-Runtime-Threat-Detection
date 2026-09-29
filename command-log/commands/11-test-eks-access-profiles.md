# Command 11: Test scoped EKS access with AWS CLI profiles (assume-role end to end)

```bash
# 1) Define 3 CLI profiles that assume the 3 roles (~/.aws/config), idempotent
insert_profile () {  # $1=profile $2=role $3=source_profile
  grep -q "\[profile ${1}\]" ~/.aws/config || cat << EoF >> ~/.aws/config

[profile ${1}]
role_arn=arn:aws:iam::${ACCOUNT_ID}:role/${2}
source_profile=${3}
EoF
}
insert_profile "admin" "k8sAdmin" "eksAdmin"
insert_profile "dev"   "k8sDev"   "eksDev"
insert_profile "integ" "k8sInteg" "eksInteg"

# 2) Write the users' long-term keys into ~/.aws/credentials (guarded; from /tmp/*.json)
#    (source profiles eksAdmin/eksDev/eksInteg hold PaulAdmin/JeanDev/PierreInteg keys)

# 3) Verify each profile assumes its role
aws sts get-caller-identity --profile dev
aws sts get-caller-identity --profile integ
aws sts get-caller-identity --profile admin

# 4) Build a per-persona kubeconfig that passes --profile to the authenticator, then test
export KUBECONFIG=/tmp/kubeconfig-dev
eksctl utils write-kubeconfig -c eks-auto
cat $KUBECONFIG | yq e '.users.[].user.exec.args += ["--profile", "dev"]' - \
  | sed 's/eks-auto./eks-auto-dev./g' > ${KUBECONFIG}.tmp && mv ${KUBECONFIG}.tmp $KUBECONFIG
kubectl run nginx-dev --image=nginx -n development     # allowed
kubectl get pods -n development                        # allowed
kubectl get pods -n integration                        # FORBIDDEN
# ...repeat for integ and admin...
```

> Concept background lives in
> [`modules-docs/kubernetes-authentication-rbac.md`](../../modules-docs/kubernetes-authentication-rbac.md)
> and [`modules-docs/iam-groups-and-roles-aws-auth.md`](../../modules-docs/iam-groups-and-roles-aws-auth.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Prove the whole access model works: each persona assumes its IAM role and gets **exactly** the cluster access we scoped — dev→development only, integ→integration only, admin→everything. |
| 2 | **What happens in Kubernetes** | Each persona authenticates as its mapped K8s user and performs RBAC-checked actions: `dev-user`/`integ-user` can create/list pods only in their namespace (denied elsewhere with **Forbidden**); `admin` (in `system:masters`) can act anywhere. Also triggers **EKS Auto Mode to launch a node** for the new pods. |
| 3 | **Which AWS service is called/used** | **AWS STS** (`sts:AssumeRole` behind each `--profile`, `sts:GetCallerIdentity`), **Amazon EKS** (API server for all `kubectl` calls), **IAM** (the assumed roles). The token→webhook→STS flow from command 04 is what authenticates each call. |

---

## 1. In one sentence

We log in as PaulAdmin/JeanDev/PierreInteg (via CLI profiles that assume the roles) and
confirm Kubernetes RBAC enforces each persona's namespace boundary.

---

## 2. How the profiles work

- `~/.aws/credentials` holds the **long-term keys** of the three users under source
  profiles `eksAdmin`/`eksDev`/`eksInteg`.
- `~/.aws/config` defines `admin`/`dev`/`integ` profiles, each with a `role_arn` (the role
  to assume) and a `source_profile` (whose keys to use to assume it).
- When you run any command with `--profile dev`, the CLI automatically calls
  `sts:AssumeRole` on `k8sDev` using JeanDev's keys, and uses the returned **temporary**
  credentials. This is the automation of the manual assume-role flow.

---

## 3. Background concepts (for beginners)

- **`source_profile`** = which stored credentials to use *to perform the assume-role*.
- **`role_arn`** = which role to become.
- **`eksctl utils write-kubeconfig`** = generates a kubeconfig whose `exec` block calls the
  authenticator to get a token. We then **append `--profile <persona>`** to that exec
  command with `yq`, so `kubectl` authenticates *as that persona*.
- **`KUBECONFIG=/tmp/kubeconfig-dev`** = point `kubectl` at a throwaway per-persona config
  so we don't disturb the default one.
- **`Forbidden`** = the RBAC authorizer rejected the action — proof the boundary works.

---

## 4. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, account `ACCOUNT_ID`).
Account ID masked as `ACCOUNT_ID` below.

### 4a. Profiles set up
```
config profiles present.
credentials profiles present.
```

### 4b. Each profile assumes its role (STS)
```
--profile dev   -> Arn: arn:aws:sts::ACCOUNT_ID:assumed-role/k8sDev/botocore-session-...
--profile integ -> Arn: arn:aws:sts::ACCOUNT_ID:assumed-role/k8sInteg/botocore-session-...
--profile admin -> Arn: arn:aws:sts::ACCOUNT_ID:assumed-role/k8sAdmin/botocore-session-...
```
Each ARN shows the expected `assumed-role/<role>` — goal achieved.

> *(Note: newly created IAM access keys can take a few seconds to become usable due to IAM
> eventual consistency; the test retried until STS returned the assumed-role ARN.)*

### 4c. `dev` persona — scoped to `development`
```
$ kubectl run nginx-dev --image=nginx -n development
pod/nginx-dev created                                    # ALLOWED

$ kubectl get pods -n development
NAME        READY   STATUS    ...                        # ALLOWED

$ kubectl get pods -n integration
Error from server (Forbidden): pods is forbidden:
  User "dev-user" cannot list resource "pods" in ... namespace "integration"   # DENIED ✓
```

### 4d. `integ` persona — scoped to `integration`
```
$ kubectl run nginx-integ --image=nginx -n integration
pod/nginx-integ created                                  # ALLOWED

$ kubectl get pods -n integration
NAME          READY   STATUS   ...                       # ALLOWED

$ kubectl get pods -n development
Error from server (Forbidden): pods is forbidden:
  User "integ-user" cannot list resource "pods" in ... namespace "development"  # DENIED ✓
```

### 4e. `admin` persona — full cluster access
```
$ kubectl run nginx-admin --image=nginx
pod/nginx-admin created                                  # ALLOWED (default ns)

$ kubectl get pods -A         # sees EVERYTHING
NAMESPACE     NAME          READY   STATUS
default       nginx-admin   1/1     Running
development   nginx-dev     1/1     Running
integration   nginx-integ   1/1     Running
```

### 4f. Bonus: EKS Auto Mode launched a node on demand
Back in [command 01](./01-kubectl-get-nodes.md) `kubectl get nodes` returned
**"No resources found"** because nothing was scheduled. Now that we created pods, Auto
Mode provisioned a node automatically:
```
$ kubectl get nodes
NAME                  STATUS   ROLES    AGE   VERSION
i-09a9f9a994c16015e   Ready    <none>   10s   v1.36.2-eks-bca9cf6
```
All three pods went from `Pending`/`ContainerCreating` to `Running` once the node was
`Ready`. This is EKS Auto Mode's on-demand scaling in action — a nice payoff of the
earlier observation.

---

## 5. What this proves (the security lesson)

| Persona | development | integration | default / cluster-wide |
|---------|-------------|-------------|------------------------|
| `dev` (dev-user) | ✅ full | ⛔ Forbidden | ⛔ Forbidden |
| `integ` (integ-user) | ⛔ Forbidden | ✅ full | ⛔ Forbidden |
| `admin` (system:masters) | ✅ | ✅ | ✅ everything |

The **entire chain works end to end**:
```
IAM user (keys) → assume IAM role (STS, via --profile) → aws-auth maps role → K8s user
→ RoleBinding → Role → namespace-scoped permission (enforced by RBAC)
```
Least-privilege access is enforced by Kubernetes RBAC, driven entirely by AWS IAM group
membership.

---

## 6. Cleanup / reset

```bash
unset KUBECONFIG                        # back to the default (admin/IDE) kubeconfig
kubectl delete pod nginx-admin          # (default ns) when done
kubectl delete pod nginx-dev -n development
kubectl delete pod nginx-integ -n integration
```

---

## 7. Handy related commands

```bash
aws sts get-caller-identity --profile dev            # Confirm which role a profile assumes
kubectl auth can-i --list -n development             # What can the current identity do here?
kubectl config get-contexts                          # Which contexts exist in this kubeconfig
```
