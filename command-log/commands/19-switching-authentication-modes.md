# Command 19: Switching between Authentication Modes (inspection only — switch NOT run)

```bash
export EKS_CLUSTER_NAME="eks-auto"

# --- SAFE, read-only inspection (these WERE run) ---
aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.{"Kubernetes Version": version, "Platform Version": platformVersion}'
aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.accessConfig'
aws eks list-access-entries --cluster-name $EKS_CLUSTER_NAME
aws sts get-caller-identity
kubectl -n kube-system get cm aws-auth -oyaml

# --- ONE-WAY switch to API (NOT run — would break our ConfigMap labs) ---
# export AUTHENTICATION_MODE="API"
# aws eks update-cluster-config --name $EKS_CLUSTER_NAME --access-config authenticationMode=$AUTHENTICATION_MODE
```

> Concept background: [`modules-docs/eks-access-management-controls.md`](../../modules-docs/eks-access-management-controls.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Understand the three auth modes and the **one-way** migration path, and inspect the cluster's current mode/entries. We intentionally **do not** switch to `API` (it would disable the `aws-auth` ConfigMap our earlier labs depend on). |
| 2 | **What happens in Kubernetes** | **Nothing changed.** Only read-only queries were run. (A real switch to `API` would disable ConfigMap-based authorization cluster-wide.) |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (`eks:DescribeCluster`, `eks:ListAccessEntries`; a switch would use `eks:UpdateClusterConfig`), **AWS STS** (`GetCallerIdentity`). `kubectl` reads the ConfigMap from the EKS API server. |

---

## 1. In one sentence

Look at the cluster's authentication mode and the two coexisting access mechanisms — and
learn why switching to `API`-only is a deliberate, irreversible decision we avoid here.

---

## 2. The three modes and the one-way rule

| Mode | Meaning |
|------|---------|
| `CONFIG_MAP` | `aws-auth` ConfigMap only (legacy). |
| `API_AND_CONFIG_MAP` | **Both** access entries **and** ConfigMap (each stores separate entries). |
| `API` | Access entries only. |

**Migration is one-way:** `CONFIG_MAP → API_AND_CONFIG_MAP → API`. You **cannot** go back.
Once you switch to `API`, the `aws-auth` ConfigMap is **no longer used** for authorization.

> **EKS Auto Mode default:** `API_AND_CONFIG_MAP` (not `CONFIG_MAP`). That's why this
> workshop demonstrates the `API_AND_CONFIG_MAP → API` migration rather than starting from
> `CONFIG_MAP`.

---

## 3. ⚠️ Why we did NOT switch to API

Our earlier labs created `aws-auth` ConfigMap mappings (`k8sDev`/`k8sInteg`/`k8sAdmin` in
[command 10](./10-configure-aws-auth-configmap.md), and the IDE console role in
[command 12](./12-console-access-mapping.md)). Switching to `API` would **disable
ConfigMap-based authorization**, breaking those mappings — and it's **irreversible**. So we
keep the cluster in `API_AND_CONFIG_MAP` and only ran the read-only inspection commands.
The switch commands are recorded above **commented out**, for reference only.

---

## 4. Actual execution (read-only) in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`). Account masked as `ACCOUNT_ID`.

### 4a. Platform / Kubernetes version
```json
{ "Kubernetes Version": "1.36", "Platform Version": "eks.14" }
```

### 4b. Current access config
```json
{ "authenticationMode": "API_AND_CONFIG_MAP" }
```
Both mechanisms are active — as expected for an Auto Mode cluster.

### 4c. Access entries (5)
```
WSParticipantRole
AWSServiceRoleForAmazonEKS
eks-auto-eks-auto-20260927091023272500000002        # cluster-creator principal (Terraform)
eks-auto-us-west-2-AmazonEKSAutoNodeRole            # Auto Mode node role
vscode-server-x86-new-auto-VSCodeInstanceRole-...   # the IDE role
```

### 4d. Current identity (the IDE role)
```
Arn: arn:aws:sts::ACCOUNT_ID:assumed-role/vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe/i-0b028d229b5f3c736
```

### 4e. `aws-auth` ConfigMap (still honored in API_AND_CONFIG_MAP)
```yaml
data:
  mapRoles: |
    - rolearn: .../role/k8sDev        username: dev-user
    - rolearn: .../role/k8sInteg      username: integ-user
    - groups: [system:masters]
      rolearn: .../role/k8sAdmin       username: admin
    - groups: [system:masters]
      rolearn: .../role/vscode-server-...-VSCodeInstanceRole-...  username: admin
  mapUsers: |
    []
```
All four mappings from commands 10 & 12 are intact and still active. This is the concrete
proof that **both** mechanisms operate side by side under `API_AND_CONFIG_MAP`: the IDE
role appears **both** as an access entry (4c) **and** in `aws-auth` (4e).

---

## 5. What a switch would look like (reference, not executed)

```bash
# One-way: enable API-only (disables aws-auth authorization)
aws eks update-cluster-config --name eks-auto --access-config authenticationMode=API

# Reverse attempts FAIL (proving one-way):
aws eks update-cluster-config --name eks-auto --access-config authenticationMode=CONFIG_MAP
# -> InvalidParameterException / not allowed
```

---

## 6. Handy related commands

```bash
aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode --output text
aws eks list-access-entries --cluster-name eks-auto
kubectl -n kube-system get cm aws-auth -oyaml
```
