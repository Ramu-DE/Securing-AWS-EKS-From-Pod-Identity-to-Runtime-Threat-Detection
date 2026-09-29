# Command 20: EKS Pod Identity access-control use cases (session tags / ABAC)

Three use cases showing how to control access to an IAM role — and to specific S3 objects
— using **Pod Identity session tags** (`aws:RequestTag/*` and `aws:PrincipalTag/*`).

> Concept background: [`modules-docs/eks-pod-identity.md`](../../modules-docs/eks-pod-identity.md).
> Builds on [command 16/17](./16-enable-eks-pod-identity.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Restrict *which* clusters/namespaces may assume an IAM role, and restrict *which* S3 objects a pod may read — all driven by the **session tags** Pod Identity attaches (cluster name, namespace, service account). |
| 2 | **What happens in Kubernetes** | Pods `app1` (sa1/ns-a) and `app2` (sa2/ns-b) are recreated repeatedly; their ability to call S3 changes as the IAM **trust policy** and **permissions policy** change. No RBAC change — this is all AWS-side authorization. |
| 3 | **Which AWS service is called/used** | **AWS IAM** (`update-assume-role-policy`, `create-policy`, `detach/attach-role-policy`), **Amazon EKS** (`create-pod-identity-association`), **Amazon S3** (`put-object` with tags, `get-object`), **AWS STS** (`AssumeRole`+`TagSession` with session tags), **AWS CloudTrail** (`lookup-events`). |

---

## 0. Key idea: Pod Identity session tags

When Pod Identity assumes the role, EKS attaches **session tags** describing the caller:
- `eks-cluster-name`, `kubernetes-namespace`, `kubernetes-service-account`.

These appear as:
- **`aws:RequestTag/*`** during the assume-role call → usable in the **trust policy** (who
  may assume).
- **`aws:PrincipalTag/*`** on the resulting session → usable in **permissions policies**
  and resource conditions (what the session may do).

This enables **ABAC** (attribute-based access control): one role, behavior varying by tag.

---

## Use case 1 — restrict the role to specific clusters (trust policy)

Updated the trust policy to only allow assumption from two **non-existent** clusters:
```json
"Condition": { "StringEquals": { "aws:RequestTag/eks-cluster-name":
   ["eks-cluster1-does-not-exist","eks-cluster2-does-not-exist"] } }
```
Then recreated `app1` and tested. **Result — DENIED** (as intended, since our real cluster
is `eks-auto`):
```
aws: [ERROR]: Error when retrieving credentials from container-role: ... (AccessDeniedException):
Unauthorized Exception! EKS does not have permissions to assume the associated role.
```
Exit code 255. **Takeaway:** the trust policy's `aws:RequestTag/eks-cluster-name` condition
scopes the role to named clusters.

### CloudTrail evidence
```
$ aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleForPodIdentity --max-items 1
EventName:  AssumeRoleForPodIdentity
eventSource: eks-auth.amazonaws.com
Username:   i-09a9f9a994c16015e            (the node)
requestParameters: { "clusterName": "eks-auto", "token": "HIDDEN_DUE_TO_SECURITY_REASONS" }
```
The `AssumeRoleForPodIdentity` call (from `eks-auth.amazonaws.com`) is auditable in
CloudTrail — showing the cluster name that requested the assumption.

---

## Use case 2 — restrict the role to specific namespaces (trust policy)

Updated the trust policy to require the real cluster **and** namespace ∈ {ns-a, ns-b}:
```json
"Condition": { "StringEquals": {
   "aws:RequestTag/eks-cluster-name": "eks-auto",
   "aws:RequestTag/kubernetes-namespace": ["ns-a","ns-b"] } }
```
Then created a Pod Identity association for **sa2/ns-b** (id `a-5aklbx1zgd2dedzit`) and
deployed **app2** in ns-b. After recreating pods:
```
app1 (ns-a) $ aws s3 ls  ->  lists ekspodidentity-... and eksworkshop-...   # ALLOWED
app2 (ns-b) $ aws s3 ls  ->  lists ekspodidentity-... and eksworkshop-...   # ALLOWED
```
> Note: app2 first returned `NoCredentials` because the new sa2/ns-b association hadn't
> propagated to the admission webhook when the pod was admitted — exactly the transient
> case the module warns about. **Recreating app2** fixed it (creds injected on the second
> create). Both namespaces are now allowed.

---

## Use case 3 — restrict access to specific S3 objects (ABAC on object tags)

### New permissions policy — condition on object tags matching the session tags
Created `eks-pod-s3-read-access-policy-s3` with:
```json
"Condition": { "StringEquals": {
  "s3:ExistingObjectTag/my-namespace":       "${aws:PrincipalTag/kubernetes-namespace}",
  "s3:ExistingObjectTag/my-service-account": "${aws:PrincipalTag/kubernetes-service-account}"
} }
```
Then **detached** the old broad policy and **attached** this one. So a pod can `GetObject`
**only** when the object's `my-namespace`/`my-service-account` tags equal the pod's own
namespace/SA session tags.

### Tagged objects created
```
customer1.txt  tagged  my-namespace=ns-a & my-service-account=sa1
customer2.txt  tagged  my-namespace=ns-b & my-service-account=sa2
```

### The verified allow/deny matrix (after recreating both pods)
```
=== sa1/ns-a (app1) ===
  GET customer1.txt -> ALLOWED         (tags ns-a/sa1 match the session)
  GET customer2.txt -> DENIED (AccessDenied)   (tags ns-b/sa2 do NOT match)

=== sa2/ns-b (app2) ===
  GET customer1.txt -> DENIED (AccessDenied)   (tags ns-a/sa1 do NOT match)
  GET customer2.txt -> ALLOWED         (tags ns-b/sa2 match the session)
```

| Pod (session tags) | customer1.txt (ns-a/sa1) | customer2.txt (ns-b/sa2) |
|--------------------|--------------------------|--------------------------|
| **app1** — ns-a / sa1 | ✅ ALLOWED | ⛔ DENIED |
| **app2** — ns-b / sa2 | ⛔ DENIED | ✅ ALLOWED |

**This is ABAC in action:** a *single* IAM role and *single* policy give each pod access to
only its own objects, purely by matching **Pod Identity session tags** against **S3 object
tags** — no per-pod policies needed.

---

## Summary — three layers of tag-based control

| Use case | Where the condition lives | Tag(s) used | Controls |
|----------|---------------------------|-------------|----------|
| 1. Cluster | Role **trust policy** | `aws:RequestTag/eks-cluster-name` | Which clusters may assume the role |
| 2. Namespace | Role **trust policy** | `aws:RequestTag/kubernetes-namespace` | Which namespaces may assume the role |
| 3. Object | **Permissions policy** | `aws:PrincipalTag/*` vs `s3:ExistingObjectTag/*` | Which S3 objects the session may read |

All three are powered by the session tags Pod Identity injects — the "role reusability /
tag-based access control" advantage from the Pod-Identity-vs-IRSA comparison.

---

## Handy related commands

```bash
aws iam get-role --role-name eks-pod-s3-read-access-role --query Role.AssumeRolePolicyDocument
aws iam list-attached-role-policies --role-name eks-pod-s3-read-access-role
aws s3api get-object-tagging --bucket ekspodidentity-$ACCOUNT_ID-$AWS_REGION --key customer1.txt
aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleForPodIdentity --max-items 5
```
