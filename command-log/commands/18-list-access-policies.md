# Command 18: List EKS access policies (and inspect current access entries)

```bash
aws eks list-access-policies
# also useful for context:
aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode --output text
aws eks list-access-entries --cluster-name eks-auto
```

> Concept background: [`modules-docs/eks-access-management-controls.md`](../../modules-docs/eks-access-management-controls.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | List the Amazon EKS-managed **access policies** you can attach to access entries (the reusable permission sets: cluster-admin/admin/edit/view, plus ~35 more). |
| 2 | **What happens in Kubernetes** | **Nothing.** This is a read-only EKS API query about EKS-managed policies; no cluster object is touched. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** only (`eks:ListAccessPolicies`, and for context `eks:DescribeCluster`, `eks:ListAccessEntries`). Note: access policies are **EKS** entities, **not** IAM policies. |

---

## 1. In one sentence

See the menu of pre-built EKS access policies (and the four Kubernetes-role-based ones this
lab uses) before wiring IAM principals to the cluster via access entries.

---

## 2. Background (for beginners)

- **Access policy** = an **EKS-managed** permission set (not an IAM policy) you attach to an
  **access entry** to grant Kubernetes permissions. Managed and versioned by AWS.
- The four based on Kubernetes **user-facing roles**:
  | Access policy | K8s role | Rough meaning |
  |---------------|----------|---------------|
  | `AmazonEKSClusterAdminPolicy` | `cluster-admin` | Full super-user, cluster-wide. |
  | `AmazonEKSAdminPolicy` | `admin` | Admin within a namespace scope. |
  | `AmazonEKSEditPolicy` | `edit` | Create/modify most objects. |
  | `AmazonEKSViewPolicy` | `view` | Read-only. |

---

## 3. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`). Account masked as `ACCOUNT_ID`.

### 3a. How many access policies exist
```
$ aws eks list-access-policies --query 'length(accessPolicies)' --output text
39
```
39 EKS-managed access policies are available (the set grows as AWS adds more).

### 3b. The four lab policies
```json
[
  { "name": "AmazonEKSAdminPolicy",        "arn": "arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy" },
  { "name": "AmazonEKSClusterAdminPolicy", "arn": "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy" },
  { "name": "AmazonEKSEditPolicy",         "arn": "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy" },
  { "name": "AmazonEKSViewPolicy",         "arn": "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy" }
]
```
Note the ARN scheme `arn:aws:eks::aws:cluster-access-policy/...` — these are **EKS**
resources, distinct from `arn:aws:iam::aws:policy/...` IAM policies.

### 3c. Current auth mode (context)
```
$ aws eks describe-cluster --name eks-auto --query cluster.accessConfig.authenticationMode --output text
API_AND_CONFIG_MAP
```
So `eks-auto` accepts **both** access entries **and** the `aws-auth` ConfigMap.

### 3d. Existing access entries on the cluster (very informative)
```
$ aws eks list-access-entries --cluster-name eks-auto
[
  "arn:aws:iam::ACCOUNT_ID:role/WSParticipantRole",
  "arn:aws:iam::ACCOUNT_ID:role/aws-service-role/eks.amazonaws.com/AWSServiceRoleForAmazonEKS",
  "arn:aws:iam::ACCOUNT_ID:role/eks-auto-eks-auto-20260927091023272500000002",
  "arn:aws:iam::ACCOUNT_ID:role/eks-auto-us-west-2-AmazonEKSAutoNodeRole",
  "arn:aws:iam::ACCOUNT_ID:role/vscode-server-x86-new-auto-VSCodeInstanceRole-Kj5ncTeGjYFe"
]
```
This confirms the module's claims with real data:
- **`AmazonEKSAutoNodeRole`** and the cluster role → **EKS Auto Mode authorizes its own
  nodes via access entries** (not `aws-auth`), matching what we noted way back in
  [command 05](./05-check-ide-role-in-aws-auth.md).
- **`WSParticipantRole`** → the workshop participant access entry created by our Terraform
  (`access_entries` block in the root `main.tf`).
- **`vscode-server-...-VSCodeInstanceRole`** → the IDE role. It has admin via an access
  entry **and** (since [command 12](./12-console-access-mapping.md)) via `aws-auth` — both
  mechanisms coexisting under `API_AND_CONFIG_MAP`.

---

## 4. How access policies get used (next steps)

An access entry is created for an IAM principal, then one or more access policies are
associated with an **access scope** (cluster-wide or specific namespaces):

```bash
aws eks create-access-entry --cluster-name eks-auto --principal-arn <IAM ARN>
aws eks associate-access-policy --cluster-name eks-auto --principal-arn <IAM ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy \
  --access-scope type=namespace,namespaces=dev
```

---

## 5. Handy related commands

```bash
aws eks list-access-policies                                   # all EKS access policies
aws eks list-access-entries --cluster-name eks-auto            # principals with entries
aws eks list-associated-access-policies --cluster-name eks-auto --principal-arn <ARN>
aws eks describe-access-entry --cluster-name eks-auto --principal-arn <ARN>
```
