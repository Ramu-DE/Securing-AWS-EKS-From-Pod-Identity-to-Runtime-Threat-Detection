# Command 13: Demonstrate the problem — a pod with no AWS identity (`NoCredentials`)

```bash
cat > eks-iam-test1.yaml <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: eks-iam-test1
  labels:
     app: s3-test
spec:
  containers:
    - name: eks-iam-test1
      image: amazon/aws-cli:latest
      args: ['s3', 'ls']
  restartPolicy: OnFailure
EOF

kubectl apply -f eks-iam-test1.yaml
kubectl get pod
kubectl logs eks-iam-test1
```

> Concept background lives in [`modules-docs/irsa.md`](../../modules-docs/irsa.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Show *why* IRSA is needed: deploy a pod that runs `aws s3 ls` with **no** AWS identity and watch it fail — motivating pod-level identity. |
| 2 | **What happens in Kubernetes** | A `Pod` (`eks-iam-test1`) is created in the `default` namespace. It starts, the container runs `aws s3 ls`, **fails with `NoCredentials`**, and (per `restartPolicy: OnFailure`) enters a restart loop showing `Error`. |
| 3 | **Which AWS service is called/used** | The pod *tries* to call **Amazon S3** (`s3:ListAllMyBuckets`) but never gets that far — it finds **no credentials** to sign the request. `kubectl` itself talks to **Amazon EKS**. No successful AWS API call occurs. |

---

## 1. In one sentence

Prove the gap: a plain pod has **no way to authenticate to AWS**, so even a trivial
`aws s3 ls` fails with `NoCredentials` — which is exactly what IRSA fixes.

---

## 2. Background concepts (for beginners)

- **Service Account** = a Kubernetes identity for a **pod/app** (not a human). By default a
  pod uses the namespace's `default` service account, which has **no AWS identity**.
- **AWS credential provider chain** = the ordered list of places the AWS SDK/CLI looks for
  credentials (env vars, config files, container/IMDS endpoints…). If *every* source is
  empty, you get `NoCredentials`.
- **IMDS (Instance Metadata Service)** = the `169.254.169.254` endpoint an EC2 instance
  uses to fetch its instance-profile credentials. On **EKS Auto Mode**, pods are **blocked
  from reaching IMDS** by default.
- **`restartPolicy: OnFailure`** = restart the container if it exits non-zero — which is
  why we see a climbing `RESTARTS` count and `Error` status.

---

## 3. Why it fails: `NoCredentials` (and why that's *good* here)

The pod has **no IAM role** on its service account, and on **EKS Auto Mode** the pod
**can't reach IMDS**, so it can't borrow the node's instance-profile credentials either.
The credential chain finds **nothing** → `NoCredentials`.

- On a **classic** cluster the same pod would instead **fall back to the node instance
  profile** via IMDS and typically fail with **`AccessDenied`**.
- Auto Mode's `NoCredentials` is a **stronger posture**: pods **cannot silently inherit
  the node's permissions**.

Either way the correct fix is the same: **give the pod its own identity (IRSA / Pod
Identity)** rather than leaning on the node — that honors **least privilege** (permissions
at the pod level, not shared across every pod on the node).

---

## 4. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, `default` namespace)

```
$ kubectl apply -f eks-iam-test1.yaml
pod/eks-iam-test1 created

# progression (a node already existed from the previous module, so no long wait)
t=10s phase=Pending  restarts=0
t=20s phase=Running  restarts=1

$ kubectl logs eks-iam-test1
aws: [ERROR]: An error occurred (NoCredentials): Unable to locate credentials.
              You can configure credentials by running "aws login".

$ kubectl get pod eks-iam-test1
NAME            READY   STATUS   RESTARTS      AGE
eks-iam-test1   0/1     Error    1 (13s ago)   23s
```

This matches the expected outcome **exactly**: the pod cannot locate any AWS credentials,
fails, and restarts (`Error`, climbing `RESTARTS`). The problem is now concretely
demonstrated — the rest of the module fixes it with IRSA.

> **Auto Mode note:** if no node had been available, Karpenter would provision one on
> demand and the pod would sit in `Pending`/`ContainerCreating` for 1–2 minutes first. In
> our case a node from [command 11](./11-test-eks-access-profiles.md) was already `Ready`,
> so it started almost immediately.

---

## 5. ⚠️ Security note — `:latest` image tag

This pod uses `amazon/aws-cli:latest`. In production, **pin an immutable tag**
(`amazon/aws-cli:2.15.0`) or a **digest** (`amazon/aws-cli@sha256:...`). Mutable `:latest`
tags are non-reproducible and a supply-chain risk.

---

## 6. Handy related commands

```bash
kubectl get pod eks-iam-test1 -w         # Watch status change live
kubectl logs eks-iam-test1               # See the NoCredentials error
kubectl describe pod eks-iam-test1       # Events, restart history, which SA it uses
kubectl get pod eks-iam-test1 -o jsonpath='{.spec.serviceAccountName}'   # -> "default"
kubectl delete pod eks-iam-test1         # Cleanup
```
