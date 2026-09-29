# Command 16: Enable EKS Pod Identity end to end

```bash
# 0) App template (namespace + SA + sleep pod), rendered with envsubst
cat > app-template.yaml <<EOF
apiVersion: v1
kind: Namespace
metadata: { name: \$NS }
---
apiVersion: v1
kind: ServiceAccount
metadata: { name: \$SA, namespace: \$NS }
---
apiVersion: v1
kind: Pod
metadata: { name: \$APP, namespace: \$NS, labels: { app: \$APP } }
spec:
  serviceAccountName: \$SA
  containers: [ { name: \$APP, image: amazon/aws-cli:latest, command: ['sleep','36000'] } ]
  restartPolicy: Never
EOF
export APP=app1 NS=ns-a SA=sa1
envsubst < app-template.yaml > $APP.yaml && kubectl apply -f $APP.yaml
kubectl -n $NS exec -it $APP -- aws s3 ls          # BEFORE: NoCredentials

# 1) IAM role whose TRUST POLICY principal is pods.eks.amazonaws.com (not OIDC!)
#    with actions sts:AssumeRole + sts:TagSession
aws iam create-role --role-name eks-pod-s3-read-access-role \
  --assume-role-policy-document file://eks-pod-s3-read-access-trust-policy.json ...
# 2) Custom S3 policy (ListAllMyBuckets + GetObject/GetObjectTagging), attach to role
# 3) EKS_CLUSTER_NAME=eks-auto  (Auto Mode: Pod Identity Agent is BUILT-IN, no add-on)
# 4) Create the association: role <-> ServiceAccount <-> namespace <-> cluster
aws eks create-pod-identity-association --cluster-name eks-auto \
  --namespace $NS --service-account $SA --role-arn $IAM_ROLE_ARN
```

> Concept background: [`modules-docs/eks-pod-identity.md`](../../modules-docs/eks-pod-identity.md).
> Contrast with IRSA: [`modules-docs/irsa-complete-flow.md`](../../modules-docs/irsa-complete-flow.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Give a pod AWS permissions the **EKS Pod Identity** way: an IAM role trusting `pods.eks.amazonaws.com` + an EKS **association** mapping role→SA→namespace — no OIDC provider, no per-cluster trust edits. |
| 2 | **What happens in Kubernetes** | Creates namespace `ns-a`, ServiceAccount `sa1`, and pod `app1`. After the association, EKS injects **container-credentials** env vars into pods using `sa1`; `aws s3 ls` then succeeds. |
| 3 | **Which AWS service is called/used** | **AWS IAM** (`CreateRole`, `CreatePolicy`, `AttachRolePolicy`), **Amazon EKS** (`create-pod-identity-association`, API server), **AWS STS** (`AssumeRole`+`TagSession` under the hood), **Amazon S3** (the pod's `s3 ls`). |

---

## 1. In one sentence

Configure Pod Identity so pods using ServiceAccount `sa1` in `ns-a` automatically assume
an S3-read IAM role — the simpler, EKS-native alternative to IRSA.

---

## 2. Key differences from IRSA (what to notice)

| | IRSA (cmd 15) | **Pod Identity (this)** |
|-|---------------|-------------------------|
| Trust principal | the cluster's **OIDC provider** ARN | **`pods.eks.amazonaws.com`** service principal |
| Setup per cluster | needs IAM OIDC provider | **none** — just an association |
| How creds reach the pod | `AWS_WEB_IDENTITY_TOKEN_FILE` (projected JWT) → `AssumeRoleWithWebIdentity` | **container credentials endpoint** (`AWS_CONTAINER_CREDENTIALS_FULL_URI`) served by the built-in agent |
| Trust actions | `sts:AssumeRoleWithWebIdentity` | `sts:AssumeRole` + **`sts:TagSession`** (enables role session tags) |

---

## 3. ⚠️ Security note — the S3 policy is broad on purpose

`s3:ListAllMyBuckets` is an **account-level** action, grantable only on `Resource: "*"`.
But `s3:GetObject`/`s3:GetObjectTagging` on `"*"` grants read to **every object in every
bucket** — far broader than a real workload should have. It's broad here to keep the step
simple. In production, restrict `Resource` to specific bucket/prefix ARNs
(`arn:aws:s3:::my-bucket/*`) and use **session-tag conditions**; otherwise you defeat the
least-privilege isolation Pod Identity is meant to provide.

---

## 4. EKS Auto Mode — no agent to install

On a traditional cluster you'd install the `eks-pod-identity-agent` add-on once. On **EKS
Auto Mode** the agent is **built-in / pre-installed** on the AWS-managed nodes, so we skip
that step and go straight to the association. (You won't see an agent pod in `kube-system`
either — it's part of the managed node software.)

---

## 5. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, region `us-west-2`). Account
masked as `ACCOUNT_ID`.

### 5a. BEFORE — sample app has no credentials
```
namespace/ns-a created; serviceaccount/sa1 created; pod/app1 created

$ kubectl -n ns-a exec app1 -- aws s3 ls
aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials.
```
> On Auto Mode the pod can't reach IMDS, so with no association it finds **no** creds
> (`NoCredentials`), same posture as the IRSA demo.

### 5b. IAM role + policy + association created
```
IAM Role created:   arn:aws:iam::ACCOUNT_ID:role/eks-pod-s3-read-access-role
policy created:     arn:aws:iam::ACCOUNT_ID:policy/eks-pod-s3-read-access-policy
policy attached

association:
  clusterName: eks-auto   namespace: ns-a   serviceAccount: sa1
  roleArn: .../eks-pod-s3-read-access-role
  associationId: a-gah4vpzj9xyk1izy7
  disableSessionTags: false
```
The role trust policy principal is **`pods.eks.amazonaws.com`** with actions
`sts:AssumeRole` + `sts:TagSession` — no OIDC, no SA-specific trust condition.

### 5c. AFTER — recreate the pod, credentials are injected
Associations apply to **new** pods, so we recreated `app1`. The injected env vars reveal
the Pod Identity mechanism:
```
AWS_CONTAINER_CREDENTIALS_FULL_URI=http://169.254.170.23/v1/credentials
AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE=/var/run/secrets/pods.eks.amazonaws.com/serviceaccount/eks-pod-identity-token
AWS_REGION=us-west-2
AWS_DEFAULT_REGION=us-west-2
AWS_STS_REGIONAL_ENDPOINTS=regional
```
> **Notice:** unlike IRSA (which set `AWS_WEB_IDENTITY_TOKEN_FILE`), Pod Identity sets
> `AWS_CONTAINER_CREDENTIALS_FULL_URI` — the SDK fetches creds from the **local agent
> endpoint** `169.254.170.23`. Different plumbing, same result.

### 5d. It works — S3 list succeeds, and the pod IS the role
```
$ kubectl -n ns-a exec app1 -- aws s3 ls
2026-09-29 03:29:59 eksworkshop-ACCOUNT_ID-us-west-2

$ kubectl -n ns-a exec app1 -- aws sts get-caller-identity
{
  "Arn": "arn:aws:sts::ACCOUNT_ID:assumed-role/eks-pod-s3-read-access-role/eks-eks-auto-app1-fdd2f42a-..."
}
```
The pod has assumed **`eks-pod-s3-read-access-role`** and can list S3 — least-privilege,
temporary, and scoped to the `sa1`/`ns-a` association. ✅

---

## 6. Notes on managing associations

- `namespace` and `serviceAccount` on an association **cannot be edited** — to change
  them, delete and recreate.
- The IAM role **can** be updated via `aws eks update-pod-identity-association`.
- Other APIs: `describe-pod-identity-association`, `delete-pod-identity-association`.

---

## 7. Handy related commands

```bash
aws eks list-pod-identity-associations --cluster-name eks-auto
aws eks describe-pod-identity-association --cluster-name eks-auto --association-id a-...
kubectl -n ns-a exec app1 -- env | grep AWS_          # see the container-credentials vars
kubectl -n ns-a exec app1 -- aws sts get-caller-identity   # confirm the assumed role
# Cleanup:
aws eks delete-pod-identity-association --cluster-name eks-auto --association-id a-...
kubectl delete ns ns-a
```
