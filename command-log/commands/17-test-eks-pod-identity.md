# Command 17: Test EKS Pod Identity (why the Pod must be recreated)

```bash
# 1) Create another S3 bucket to list
export S3_BUCKET="ekspodidentity-$ACCOUNT_ID-$AWS_REGION"
aws s3 mb s3://$S3_BUCKET --region $AWS_REGION

# 2) Test from the pod (fails if the pod predates the association)
kubectl -n $NS exec -it $APP -- aws s3 ls        # -> NoCredentials if pod is older than the association

# 3) Delete + recreate the pod so credentials are injected at creation time
kubectl -n $NS delete pod $APP --force --grace-period=0
kubectl apply -f $APP.yaml

# 4) Test again -> now it lists the buckets
kubectl -n $NS exec -it $APP -- aws s3 ls
```

> Concept background: [`modules-docs/eks-pod-identity.md`](../../modules-docs/eks-pod-identity.md).
> Follows [command 16](./16-enable-eks-pod-identity.md) (creating the association).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Verify Pod Identity works and learn the key operational rule: **credentials are injected only at pod creation**, so a pod created *before* its association must be **recreated** to pick up access. |
| 2 | **What happens in Kubernetes** | Deletes and recreates pod `app1` in `ns-a`. On recreation, EKS injects the container-credentials env vars (because `sa1` now has an association), and `aws s3 ls` succeeds. |
| 3 | **Which AWS service is called/used** | **Amazon S3** (`mb` creates a bucket; the pod's `s3 ls` = `ListAllMyBuckets`), **Amazon EKS** (API server + Pod Identity injection), **AWS STS** (`AssumeRole` under the hood via the association). |

---

## 1. In one sentence

Confirm the associated ServiceAccount grants S3 access — and see firsthand that the pod
must be **recreated after** the association is made for credentials to appear.

---

## 2. The key lesson: injection happens at pod creation

Pod Identity credentials (and the env vars pointing to them) are **injected into a pod
only when it is created**. If the association didn't exist when the pod started, **no
credentials were injected**, and on EKS Auto Mode the pod **can't fall back** to the node
instance profile — so it stays at `NoCredentials`.

**Fix:** delete and recreate the pod. On recreation the mutating admission flow sees the
association for `sa1` and injects the credentials.

> This is a common real-world gotcha: creating/attaching an association does **not**
> retroactively fix already-running pods. Restart the workload (delete pod / rollout
> restart the Deployment).

---

## 3. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, `ns-a` namespace). Account
masked as `ACCOUNT_ID`.

### 3a. New bucket created
```
$ aws s3 mb s3://ekspodidentity-ACCOUNT_ID-us-west-2
make_bucket: ekspodidentity-ACCOUNT_ID-us-west-2
```

### 3b. Delete + recreate the pod
```
$ kubectl -n ns-a delete pod app1 --force --grace-period=0
pod "app1" force deleted from ns-a namespace

$ kubectl apply -f app1.yaml
pod/app1 created           # phase: Pending -> Running
```

### 3c. S3 access now works — lists BOTH workshop buckets
```
$ kubectl -n ns-a exec app1 -- aws s3 ls
2026-09-29 03:37:50 ekspodidentity-ACCOUNT_ID-us-west-2
2026-09-29 03:29:59 eksworkshop-ACCOUNT_ID-us-west-2
```
The pod (via ServiceAccount `sa1`, associated with `eks-pod-s3-read-access-role`) can now
list all S3 buckets — including the new `ekspodidentity-...` one and the earlier
`eksworkshop-...` one from the IRSA lab. ✅

> Note: in [command 16](./16-enable-eks-pod-identity.md) we had already recreated `app1`
> once, so it was working before this step too. Recreating it here after adding the new
> bucket cleanly demonstrates the create-time-injection rule and shows the fresh bucket in
> the listing.

---

## 4. Why `--force --grace-period=0`?

- `--force --grace-period=0` deletes the pod **immediately** without waiting for graceful
  termination — fine for a throwaway test pod, and avoids waiting on the `sleep 36000`
  process. (Avoid `--force` on stateful production workloads, which need graceful
  shutdown.)

---

## 5. Handy related commands

```bash
kubectl -n ns-a exec app1 -- aws sts get-caller-identity    # confirm the assumed role
kubectl -n ns-a exec app1 -- env | grep AWS_                # container-credentials vars
aws s3 ls                                                    # list buckets from the IDE (for comparison)
# For a Deployment instead of a bare Pod, use: kubectl rollout restart deploy/<name> -n <ns>
```
