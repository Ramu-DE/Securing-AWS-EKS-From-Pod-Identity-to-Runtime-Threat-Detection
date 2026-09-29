# Module: Detective Controls (GuardDuty EKS Protection, CloudWatch Log Insights, CloudTrail)

Preventive controls (RBAC, network policies, PSA) stop bad things; **detective controls**
tell you *what actually happened* and surface threats. On EKS: **GuardDuty EKS Protection**,
**EKS control-plane audit logs** analyzed with **CloudWatch Log Insights**, and
**CloudTrail** for the AWS API layer. Pairs with the hands-on Log Insights query in
[`command-log/commands/28-detective-controls-log-insights.md`](../command-log/commands/28-detective-controls-log-insights.md).

---

## 1. The three detective layers

| Layer | Sees | Source |
|-------|------|--------|
| **CloudTrail** | AWS API calls (who called `eks:*`, `iam:*`, assumed roles, `AssumeRoleForPodIdentity`, …) | AWS control plane |
| **EKS control-plane logs** | Kubernetes API server activity (audit, authenticator, api, scheduler, controllerManager) | EKS → CloudWatch Logs |
| **GuardDuty EKS Protection** | Threats — audit-log anomalies + **runtime** behavior (via the eBPF runtime agent) | GuardDuty ML/threat intel |

Together: CloudTrail = AWS-level "who did what to the cluster resource"; EKS audit logs =
"what happened inside the Kubernetes API"; GuardDuty = "which of those is suspicious".

---

## 2. GuardDuty EKS Protection

Two capabilities:
- **EKS Audit Log Monitoring** — GuardDuty consumes EKS control-plane audit logs and flags
  anomalies (e.g. `exec` into a system pod, anonymous access, privilege escalation, a
  service account suddenly listing secrets).
- **EKS Runtime Monitoring** — a GuardDuty **runtime agent** (eBPF) on the nodes detects
  on-host behavior (crypto-mining, reverse shells, suspicious binaries, container escape).

Findings appear in the GuardDuty console, and can fan out via **EventBridge → SNS/Lambda**
for alerting/auto-remediation (the workshop's SNS/EventBridge screenshots).

> ⚠️ **Account-level enablement — flagged, NOT enabled.** Verified live: **no GuardDuty
> detector exists** in this account/region. Enabling GuardDuty + EKS Protection + Runtime
> Monitoring is an **account-wide, cost-bearing** change. Enable only with explicit
> approval:
> ```bash
> aws guardduty create-detector --enable
> aws guardduty update-detector --detector-id <id> \
>   --features '[{"Name":"EKS_AUDIT_LOGS","Status":"ENABLED"},{"Name":"EKS_RUNTIME_MONITORING","Status":"ENABLED"}]'
> ```
> You can generate **sample findings** (`create-sample-findings`) to exercise the pipeline
> without real attacks.

---

## 3. EKS control-plane logs + CloudWatch Log Insights (done live — cmd 28)

EKS can ship 5 control-plane log types to CloudWatch Logs
(`/aws/eks/<cluster>/cluster`). Verified live on `eks-auto`:
- **Enabled:** `api`, `audit`, `scheduler` (pre-enabled by our Terraform so historical data
  exists for this lab).
- **Disabled:** `authenticator`, `controllerManager` (participants can enable as a
  before/after step).

**Log Insights** runs SQL-like queries over the audit log. Example (executed live):
```
fields @timestamp, verb, user.username, objectRef.resource
| filter @logStream like /kube-apiserver-audit/
| stats count(*) as cnt by verb | sort cnt desc
```
Useful investigative queries:
- Who deleted/patched resources: `filter verb in ["delete","patch"]` by `user.username`.
- Anonymous/`system:anonymous` access attempts.
- Access to Secrets: `filter objectRef.resource="secrets"`.
- Failed (forbidden) requests: `filter responseStatus.code>=400`.

---

## 4. CloudTrail (AWS API layer)

CloudTrail records AWS API calls. Verified live: trails exist in the account
(`EventEngineTrail`, workshop CloudTrail). Relevant to EKS security:
- `AssumeRoleForPodIdentity` (we saw this in cmd 20) — which cluster/pod requested AWS creds.
- `eks:*` config changes (auth-mode switch, access-entry create), `iam:*` changes.
- Correlate CloudTrail (AWS side) with EKS audit logs (K8s side) for full-picture forensics.

---

## 5. Best practices

- **Enable audit logging before you need it** — queries need pre-existing data (our cluster
  pre-enables `audit`). Retain logs per your compliance window.
- **Enable GuardDuty EKS Protection** (audit + runtime) in production; route findings to
  Security Hub / SNS / an incident pipeline.
- **Alert, don't just log** — wire EventBridge rules on high-severity findings to SNS/Slack
  and, where safe, auto-remediation (isolate pod, revoke creds).
- **Least-privilege the log/monitoring access itself** and protect logs from tampering.

---

## 6. Relation to the rest of the workshop

- Detective controls are the "assume breach / verify" layer complementing the preventive
  modules (RBAC/access-entries, network policies, PSA/Gatekeeper, image security).
- The audit log this module queries is the **same** data GuardDuty EKS Audit Log Monitoring
  consumes — enabling logging is the foundation for both manual (Log Insights) and automated
  (GuardDuty) detection.
