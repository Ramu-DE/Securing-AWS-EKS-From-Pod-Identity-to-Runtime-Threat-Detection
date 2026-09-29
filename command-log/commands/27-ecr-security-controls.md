# Command 27: ECR security controls (scan-on-push, immutable tags, repo policy, lifecycle)

```bash
REPO=eks-workshop-secure-repo

# 1) Create repo: scan-on-push + IMMUTABLE tags + AES256 encryption
aws ecr create-repository --repository-name $REPO \
  --image-scanning-configuration scanOnPush=true \
  --image-tag-mutability IMMUTABLE \
  --encryption-configuration encryptionType=AES256

# 2) Repository policy: allow pull only from this account (least privilege)
aws ecr set-repository-policy --repository-name $REPO --policy-text file://ecr-repo-policy.json

# 3) Lifecycle policy: expire untagged >7d; keep only last 10 tagged
aws ecr put-lifecycle-policy --repository-name $REPO --lifecycle-policy-text file://ecr-lifecycle.json

# (read-only) account registry scan type: BASIC vs ENHANCED(Inspector)
aws ecr get-registry-scanning-configuration --query 'scanningConfiguration.scanType'
```

> Concept background: [`modules-docs/image-security.md`](../../modules-docs/image-security.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Harden a container image repo: automatic CVE scanning, tamper-proof tags, at-rest encryption, least-privilege pull, and automatic cleanup of stale images. |
| 2 | **What happens in Kubernetes** | **Nothing directly** — these are registry-side controls. They affect the cluster indirectly (only hardened, scanned images should be pulled by pods). |
| 3 | **Which AWS service is called/used** | **Amazon ECR** (`create-repository`, `set-repository-policy`, `put-lifecycle-policy`, `get-registry-scanning-configuration`). No cluster call. |

---

## 1. In one sentence

Create a hardened ECR repository with scan-on-push, immutable tags, encryption, a
least-privilege pull policy, and a lifecycle cleanup policy.

---

## 2. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, region `us-west-2`). Account masked as `ACCOUNT_ID`.

### 2a. Repository created + verified
```
created: eks-workshop-secure-repo | scanOnPush=True | tagMutability=IMMUTABLE
{ "scanOnPush": true, "tagMutability": "IMMUTABLE", "encryption": "AES256" }
```

### 2b. Repository policy (least-privilege pull) — verified
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowPullFromThisAccount",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::ACCOUNT_ID:root" },
    "Action": ["ecr:GetDownloadUrlForLayer","ecr:BatchGetImage","ecr:BatchCheckLayerAvailability"]
  }]
}
```

### 2c. Lifecycle policy — verified
```
rule 1: Expire untagged >7d
rule 2: Keep only last 10 tagged
```

### 2d. Account registry scan type (read-only)
```
BASIC
```
→ **ENHANCED** (Amazon Inspector) is **not** enabled. That's an account-level, cost-bearing
change — **flagged, not enabled** (see the module doc / Inspector section).

---

## 3. What each control buys you

- **scanOnPush=true** → every push is auto-scanned for OS-package CVEs (BASIC). Upgrade to
  Inspector ENHANCED for deep + continuous scanning.
- **IMMUTABLE tags** → a tag can't be silently overwritten with different content
  (reproducibility + anti-tamper).
- **AES256 encryption** → images encrypted at rest (use KMS for customer-managed keys).
- **Repository policy** → only this account's principals can pull (not public/`*`).
- **Lifecycle policy** → untagged images expire after 7 days; only the last 10 tagged are
  kept — shrinking attack surface and cost.

---

## 4. Handy related commands

```bash
aws ecr describe-repositories --repository-names eks-workshop-secure-repo
aws ecr get-repository-policy   --repository-name eks-workshop-secure-repo
aws ecr get-lifecycle-policy    --repository-name eks-workshop-secure-repo
aws ecr describe-image-scan-findings --repository-name eks-workshop-secure-repo --image-id imageTag=<tag>
# Cleanup:
aws ecr delete-repository --repository-name eks-workshop-secure-repo --force
```
