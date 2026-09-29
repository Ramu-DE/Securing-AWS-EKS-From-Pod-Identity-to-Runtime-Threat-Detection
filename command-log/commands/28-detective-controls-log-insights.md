# Command 28: Detective Controls — Log Insights query + GuardDuty/CloudTrail inspection

```bash
# (read-only) Is GuardDuty enabled?
aws guardduty list-detectors

# (read-only) CloudTrail trails + EKS control-plane logging config
aws cloudtrail list-trails
aws eks describe-cluster --name eks-auto --query 'cluster.logging.clusterLogging'

# CloudWatch Log Insights over the EKS AUDIT log (real detective query)
aws logs start-query --log-group-name /aws/eks/eks-auto/cluster \
  --start-time <t-2h> --end-time <now> \
  --query-string 'fields @timestamp, verb, user.username, objectRef.resource
      | filter @logStream like /kube-apiserver-audit/
      | stats count(*) as cnt by verb | sort cnt desc | limit 10'
aws logs get-query-results --query-id <id>
```

> Concept background: [`modules-docs/detective-controls.md`](../../modules-docs/detective-controls.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Inspect the cluster's detective posture (GuardDuty, CloudTrail, EKS logging) and **query the real EKS audit log** with Log Insights to see who did what. |
| 2 | **What happens in Kubernetes** | **Nothing changed.** Read-only. The queried data is the EKS control-plane **audit log** already shipped to CloudWatch. |
| 3 | **Which AWS service is called/used** | **Amazon GuardDuty** (`list-detectors`), **AWS CloudTrail** (`list-trails`), **Amazon EKS** (`describe-cluster`), **CloudWatch Logs Insights** (`start-query`/`get-query-results`). |

---

## 1. In one sentence

Confirm what threat-detection is on, then run a real Log Insights query over the EKS audit
log to demonstrate Kubernetes API forensics.

---

## 2. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, region `us-west-2`).

### 2a. GuardDuty — NOT enabled (flagged)
```
$ aws guardduty list-detectors
detectors: <none>
```
No detector exists → GuardDuty (and EKS Protection/Runtime Monitoring) is **off**. Enabling
it is an account-level, cost-bearing change — **flagged, not enabled** (see module doc §2).

### 2b. CloudTrail — trails present
```
$ aws cloudtrail list-trails
CloudTrailStreamStack-...-WSAnalyticsCloudTrail...   EventEngineTrail
```
AWS API activity is being recorded (workshop-provisioned trails).

### 2c. EKS control-plane logging — enabled subset
```
enabled: ["api","audit","scheduler"]
disabled: ["authenticator","controllerManager"]
log group: /aws/eks/eks-auto/cluster   (exists)
```
`audit` is enabled (by our Terraform), so historical data exists to query — exactly what
this lab needs.

### 2d. Log Insights query over the AUDIT log — REAL RESULTS
Top Kubernetes API verbs in the last 2 hours:
```
verb     count
------   ------
get      69410
update   37026
watch    13026
list      5752
create    1160
patch      ...
```
This is genuine detective-control output: the audit log shows the shape of API activity
against the cluster. Swapping the query lets you hunt specific behavior — deletes/patches by
user, access to `secrets`, `system:anonymous` attempts, or `responseStatus.code>=400`
(forbidden) events.

---

## 3. Why this matters

- The **audit log** we just queried is the **same source** GuardDuty EKS Audit Log
  Monitoring consumes — enabling logging underpins both manual (Log Insights) and automated
  (GuardDuty) detection.
- Correlate with **CloudTrail** (AWS side, e.g. `AssumeRoleForPodIdentity` from cmd 20) for
  end-to-end forensics across the AWS and Kubernetes layers.

---

## 4. Useful investigative Log Insights queries

```
# who deleted/patched what
fields @timestamp, user.username, verb, objectRef.resource, objectRef.name
| filter verb in ["delete","patch"] | sort @timestamp desc

# access to Secrets
| filter objectRef.resource = "secrets"

# forbidden / failed requests
| filter responseStatus.code >= 400

# anonymous access
| filter user.username = "system:anonymous"
```

---

## 5. Handy related commands (enablement — flagged)

```bash
aws guardduty create-detector --enable                       # (account-level; get approval)
aws guardduty create-sample-findings --detector-id <id> --finding-types <types>
aws eks update-cluster-config --name eks-auto \
  --logging '{"clusterLogging":[{"types":["authenticator"],"enabled":true}]}'   # enable more log types
```
