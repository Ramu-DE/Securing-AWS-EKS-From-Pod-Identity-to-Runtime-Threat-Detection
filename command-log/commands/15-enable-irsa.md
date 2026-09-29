# Command 15: Enable IRSA end to end (OIDC provider → SA+role → working S3 access)

```bash
# 1) Get the cluster's OIDC issuer id; check if an IAM OIDC provider already exists
oidc_id=$(aws eks describe-cluster --name eks-auto --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)
aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4
# Create it once if missing (idempotent):
eksctl utils associate-iam-oidc-provider --cluster eks-auto --approve

# 2) Find the S3 read-only policy ARN
aws iam list-policies --query 'Policies[?PolicyName==`AmazonS3ReadOnlyAccess`].Arn'

# 3) Create an IAM role bound to a K8s ServiceAccount (iam-test) with that policy
eksctl create iamserviceaccount \
    --name iam-test --cluster eks-auto \
    --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
    --approve --override-existing-serviceaccounts
kubectl describe sa iam-test          # note the eks.amazonaws.com/role-arn annotation

# 4) Prove it works: bucket + a pod using the SA to run `aws s3 ls`
aws s3 mb s3://eksworkshop-$ACCOUNT_ID-$AWS_REGION --region $AWS_REGION
# pod eks-iam-test3 with serviceAccountName: iam-test, args ['s3','ls'] -> Completed
# 5) Inspect the injected token + env vars on a sleep pod (eks-iam-test4)
```

> Concept + diagram background:
> [`modules-docs/irsa.md`](../../modules-docs/irsa.md),
> [`modules-docs/irsa-complete-flow.md`](../../modules-docs/irsa-complete-flow.md).
> Builds on [command 13](./13-irsa-nocredentials-demo.md) (the failure) and
> [command 14](./14-projected-service-account-token.md) (the base token).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Wire up IRSA fully and prove it: register the OIDC provider, create a ServiceAccount bound to an S3-read-only IAM role, and watch a pod using that SA successfully list S3 — fixing the `NoCredentials` failure from command 13. |
| 2 | **What happens in Kubernetes** | Creates ServiceAccount `iam-test` (annotated with the role ARN). Pods using it get a **2nd projected token** (audience `sts.amazonaws.com`) and `AWS_*` env vars injected by the **EKS Pod Identity webhook**. Test pods run and `Complete`/`Run`. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (`DescribeCluster`, API server), **AWS IAM** (`ListPolicies`; eksctl creates the role via a **CloudFormation** stack), **Amazon S3** (`mb`, and the pod's `s3 ls` = `ListAllMyBuckets`), **AWS STS** (`AssumeRoleWithWebIdentity` under the hood), **IAM OIDC provider**. |

---

## 1. In one sentence

Give the `iam-test` ServiceAccount its own IAM role via OIDC federation, so any pod using
that SA gets **least-privilege, temporary** S3 access — no keys, no node role.

---

## 2. The setup steps explained

| Step | What / why |
|------|-----------|
| **OIDC provider** | An IAM **OIDC identity provider** must exist for the cluster's issuer URL so STS will trust the cluster's tokens. Needed once per cluster. |
| **Policy ARN** | We use the AWS-managed **`AmazonS3ReadOnlyAccess`** (get/list on all buckets). |
| **`eksctl create iamserviceaccount`** | Creates the IAM role (trust policy scoped to `system:serviceaccount:default:iam-test`), attaches the policy, and creates the K8s SA annotated with the role ARN — all via a CloudFormation stack. |

> ⚠️ **`AmazonS3ReadOnlyAccess` is broad on purpose** (`Resource: *`). In production, attach
> a **customer-managed** policy listing only the specific bucket/prefix ARNs the workload
> needs. A scoped IAM policy + a per-ServiceAccount IRSA role is what actually delivers
> least privilege.

---

## 3. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, region `us-west-2`). Account
masked as `ACCOUNT_ID`.

### 3a. OIDC provider — already present
```
oidc_id = 5CC109EF2CCB404415FA350577E27AF5
list-open-id-connect-providers | grep -> 5CC109EF2CCB404415FA350577E27AF5   # already exists
associate-iam-oidc-provider -> "IAM Open ID Connect provider is already associated"
```
> This `oidc_id` is exactly the `iss` we saw in the projected token in
> [command 14](./14-projected-service-account-token.md) — the same trust anchor.

### 3b. Policy ARN
```
arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
```

### 3c. ServiceAccount + role created (via CloudFormation)
```
created serviceaccount "default/iam-test"

$ kubectl describe sa iam-test
Annotations: eks.amazonaws.com/role-arn:
  arn:aws:iam::ACCOUNT_ID:role/eksctl-eks-auto-addon-iamserviceaccount-defau-Role1-qtMhmT9hKiR8
```
The SA now carries the **`eks.amazonaws.com/role-arn`** annotation — the trigger the
webhook keys off.

### 3d. It works! (`eks-iam-test3` lists S3)
```
$ aws s3 mb s3://eksworkshop-ACCOUNT_ID-us-west-2
make_bucket: eksworkshop-ACCOUNT_ID-us-west-2

$ kubectl get pod eks-iam-test3
NAME            READY   STATUS      RESTARTS   AGE
eks-iam-test3   0/1     Completed   0          5s

$ kubectl logs eks-iam-test3
2026-09-29 03:29:59 eksworkshop-ACCOUNT_ID-us-west-2
```
Compare to [command 13](./13-irsa-nocredentials-demo.md): the *same* `aws s3 ls` that
failed with `NoCredentials` now **succeeds** and `Completed`, purely because the pod uses
the `iam-test` ServiceAccount. **This is IRSA working.**

### 3e. Inspecting the injected token + env vars (`eks-iam-test4`)

**Injected `AWS_*` env vars** (added by the Pod Identity webhook):
```
AWS_STS_REGIONAL_ENDPOINTS=regional
AWS_DEFAULT_REGION=us-west-2
AWS_REGION=us-west-2
AWS_ROLE_ARN=arn:aws:iam::ACCOUNT_ID:role/eksctl-eks-auto-addon-iamserviceaccount-defau-Role1-qtMhmT9hKiR8
AWS_WEB_IDENTITY_TOKEN_FILE=/var/run/secrets/eks.amazonaws.com/serviceaccount/token
```

**The TWO projected token volumes:**
```
volume=aws-iam-token          audience=sts.amazonaws.com     expirationSeconds=86400  path=token
volume=kube-api-access-hhfmc  audience=(default: k8s api)    expirationSeconds=3607   path=token
```
- `kube-api-access-*` → the original SA token (audience = K8s API server, ~1h) from
  command 14.
- `aws-iam-token` → **the second token injected by the webhook**, audience
  **`sts.amazonaws.com`**, mounted at a *different* path
  `/var/run/secrets/eks.amazonaws.com/serviceaccount/token`, longer 24h expiry.

**The decoded AWS token payload (REAL):**
```json
{
  "aud": ["sts.amazonaws.com"],
  "iss": "https://oidc.eks.us-west-2.amazonaws.com/id/5CC109EF2CCB404415FA350577E27AF5",
  "sub": "system:serviceaccount:default:iam-test",
  "exp": 1790739022, "iat": 1790652622,
  "kubernetes.io": { "namespace": "default", "serviceaccount": { "name": "iam-test" }, "pod": {"name":"eks-iam-test4"} }
}
```

---

## 4. Reading the AWS token vs the base token

| Field | Base token (cmd 14) | AWS token (this cmd) |
|-------|---------------------|----------------------|
| `aud` | `https://kubernetes.default.svc` (K8s API) | **`sts.amazonaws.com`** (AWS STS) |
| `sub` | `system:serviceaccount:default:default` | **`system:serviceaccount:default:iam-test`** |
| `iss` | cluster OIDC provider | **same** cluster OIDC provider |
| expiry | ~1 hour | **24 hours** (tunable via `eks.amazonaws.com/token-expiration`) |

The AWS token's `aud` and `sub` are exactly what the IAM role's **trust policy conditions**
check (see `iam-role-trust-policy.png` in the flow doc). That's how STS confirms only
`default/iam-test` pods may assume this role.

---

## 5. How the full flow just executed (mapping to the diagram)

1. Pod created → **API server** triggers the **Pod Identity webhook**.
2. Webhook reads the SA's role-arn annotation → injects `AWS_ROLE_ARN`,
   `AWS_WEB_IDENTITY_TOKEN_FILE`, and the `aws-iam-token` projected volume.
3. `aws s3 ls` → SDK reads those env vars → calls **STS `AssumeRoleWithWebIdentity`** with
   the `sts.amazonaws.com` token.
4. STS verifies the token via the **OIDC provider** + checks trust-policy `aud`/`sub`.
5. STS returns temp creds → the CLI lists the bucket. ✅

---

## 6. Cleanup / handy commands

```bash
kubectl delete pod eks-iam-test1 eks-iam-test2 eks-iam-test3 eks-iam-test4
aws s3 rb s3://eksworkshop-$ACCOUNT_ID-$AWS_REGION            # remove bucket (must be empty)
eksctl delete iamserviceaccount --name iam-test --cluster eks-auto   # removes SA + CFN role
kubectl describe sa iam-test                                  # see the role-arn annotation
```
