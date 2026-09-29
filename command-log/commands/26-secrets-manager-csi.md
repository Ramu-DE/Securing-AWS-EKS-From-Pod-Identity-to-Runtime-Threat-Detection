# Command 26: Mount an AWS Secrets Manager secret into a pod (Secrets Store CSI + ASCP)

```bash
# 1) Create the secret
aws secretsmanager create-secret --name eks-workshop-db-secret \
  --secret-string '{"username":"appuser","password":"***"}'

# 2) Install the Secrets Store CSI Driver WITH tokenRequests audience (required!)
helm upgrade --install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  -n kube-system --set syncSecret.enabled=true \
  --set 'tokenRequests[0].audience=sts.amazonaws.com' --wait

# 3) Install the AWS provider (from the official manifest to avoid SA name collision)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# 4) Per-SA IRSA role scoped to the ONE secret ARN + create the SA (eksctl)
eksctl create iamserviceaccount --name secrets-sa --namespace secrets-demo --cluster eks-auto \
  --attach-policy-arn arn:aws:iam::<acct>:policy/eks-secrets-csi-policy --approve --override-existing-serviceaccounts

# 5) SecretProviderClass + a pod mounting the secret as a file
kubectl apply -f - <<'EOF'
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata: { name: eks-workshop-db-spc, namespace: secrets-demo }
spec:
  provider: aws
  parameters:
    region: us-west-2
    objects: |
      - objectName: "eks-workshop-db-secret"
        objectType: "secretsmanager"
EOF
# pod mounts CSI volume driver=secrets-store.csi.k8s.io, secretProviderClass=eks-workshop-db-spc
```

> Concept background: [`modules-docs/secrets-manager-csi.md`](../../modules-docs/secrets-manager-csi.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Mount a Secrets Manager secret into a pod **as a file** — no secrets in images/manifests — with pod-scoped read access via IRSA. |
| 2 | **What happens in Kubernetes** | Installs the CSI driver + AWS provider (DaemonSets in `kube-system`); creates a `SecretProviderClass`; a pod using `secrets-sa` mounts the secret at `/mnt/secrets/…`. |
| 3 | **Which AWS service is called/used** | **AWS Secrets Manager** (`CreateSecret`, `GetSecretValue`/`DescribeSecret` by the provider), **AWS STS** (IRSA `AssumeRoleWithWebIdentity`), **IAM** (per-SA role/policy + CloudFormation via eksctl), **Amazon EKS** (API server). |

---

## 1. In one sentence

Prove a pod can read a Secrets Manager secret as a mounted file using the Secrets Store CSI
driver + AWS provider + a least-privilege IRSA role.

---

## 2. Actual execution (incl. the two fixes)

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, region `us-west-2`).

### 2a. Secret + driver + provider
```
Secret created: arn:aws:secretsmanager:us-west-2:ACCOUNT_ID:secret:eks-workshop-db-secret-KIRmoG
CSI driver pods: csi-secrets-store-...  3/3 Running (x2)
AWS provider pods: csi-secrets-store-provider-aws-...  1/1 Running (x2)
csidriver secrets-store.csi.k8s.io registered
```

### 2b. First mount attempt → **FAILED** (tokenRequests missing)
```
MountVolume.SetUp failed: CSI token error: serviceAccount.tokens not provided
  - ensure tokenRequests is configured in CSIDriver spec
```
**Fix:** reinstalled the driver with `tokenRequests[0].audience=sts.amazonaws.com`:
```
$ kubectl get csidriver secrets-store.csi.k8s.io -o jsonpath='{.spec.tokenRequests}'
[{"audience":"sts.amazonaws.com"}]
```

### 2c. Second attempt → **FAILED** (no IAM role on SA)
```
MountVolume.SetUp failed: An IAM role must be associated with service account secrets-sa (namespace: secrets-demo)
```
**Fix:** created an **IRSA** role for the SA (the AWS provider resolves IRSA reliably),
scoped to the single secret ARN:
```
SA annotation eks.amazonaws.com/role-arn:
  arn:aws:iam::ACCOUNT_ID:role/eksctl-eks-auto-addon-iamserviceaccount-secre-Role1-YDfI1twr17Zi
```

### 2d. SUCCESS — secret mounted and readable
```
$ kubectl -n secrets-demo get pod secrets-app
secrets-app   1/1   Running

$ kubectl -n secrets-demo exec secrets-app -- ls -l /mnt/secrets
-rw-r--r-- 1 root root 51 ... eks-workshop-db-secret

$ kubectl -n secrets-demo exec secrets-app -- cat /mnt/secrets/eks-workshop-db-secret
{"username":"appuser","password":"<PASSWORD-REDACTED>"}
```
The pod reads the secret **as a file** — it never handled AWS credentials or called Secrets
Manager itself. The provider assumed the SA's **IRSA role** (scoped to just this secret) to
fetch it. ✅

> Secret value is **redacted** in this log; the real content was returned correctly in the
> live run.

---

## 3. Lessons

- Install the CSI driver **with** `tokenRequests[0].audience=sts.amazonaws.com`.
- The provider needs the SA to resolve to an IAM role — **IRSA annotation** is the reliable
  path; scope the policy to the **exact secret ARN**.
- Install the AWS provider from its **manifest** (Helm chart collides on the shared
  `secrets-store-csi-driver` SA name).

---

## 4. Cleanup / handy commands

```bash
kubectl -n secrets-demo get secretproviderclass,pod
kubectl -n secrets-demo exec secrets-app -- ls /mnt/secrets
# Cleanup:
kubectl delete ns secrets-demo
eksctl delete iamserviceaccount --name secrets-sa --namespace secrets-demo --cluster eks-auto
aws secretsmanager delete-secret --secret-id eks-workshop-db-secret --force-delete-without-recovery
```
