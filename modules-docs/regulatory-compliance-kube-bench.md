# Module: Regulatory Compliance — CIS Benchmark with kube-bench

Assess the cluster against the **CIS Kubernetes / Amazon EKS Benchmark** using
**kube-bench**, the open-source tool that checks node and cluster configuration against CIS
controls. This is **concept + provisioning-flagged** on EKS Auto Mode (explained below).

---

## 1. What is kube-bench / the CIS Benchmark?

- The **CIS Kubernetes Benchmark** (and the **CIS Amazon EKS Benchmark**) is a set of
  hardening recommendations: control-plane flags, kubelet config, file permissions on node
  components, RBAC hygiene, etc.
- **kube-bench** (from Aqua Security) runs those checks and reports **PASS / FAIL / WARN /
  INFO** per control, with remediation guidance.

On EKS the **control plane is AWS-managed** (you can't check its files), so kube-bench uses
the **EKS-specific benchmark** and focuses on what you *can* control: the **node**
(kubelet, config files, permissions) and cluster-level RBAC/policy.

---

## 2. ⚠️ The EKS Auto Mode constraint (key finding)

Our primary cluster `eks-auto` runs **EKS Auto Mode**, whose nodes are **Bottlerocket** —
a minimal, locked-down OS you **cannot SSH into** and which has **no general-purpose shell
on the host**. Node-level kube-bench (which reads host files like
`/etc/kubernetes/kubelet/kubelet-config.json`) therefore **cannot run the usual way** on
Auto Mode nodes.

This is itself a **security posture win**: Auto Mode nodes are immutable and
inaccessible, removing a whole class of node-hardening findings — but it means the
traditional "run kube-bench on the node" lab needs a **classic node**.

### The workshop's approach (in this repo)
[`kube-bench/`](../kube-bench/) Terraform provisions a **temporary AL2023 managed node
group** attached to `eks-auto` (plus the `vpc-cni`+`kube-proxy` add-ons a classic node
needs) specifically so kube-bench can run on a shell-accessible node, then it's destroyed.

```
Lab 0: terraform apply  (kube-bench/)  -> adds AL2023 node group cis-al2023-ng
Lab 1: run kube-bench on that node (SSM Session Manager or a Job pinned to it)
Lab 5: terraform destroy (kube-bench/) -> removes the node group
```

> ⚠️ **Provisioning-flagged, not applied.** Adding a classic managed node group changes the
> data plane (extra EC2 cost, vpc-cni ConfigMap, classic scheduling) and is intentionally
> kept out of the main cluster. Apply `kube-bench/` only with explicit approval; destroy
> after the assessment.

---

## 3. How you run kube-bench (once a classic node exists)

As a Kubernetes **Job** pinned (nodeSelector/toleration) to the AL2023 node:
```yaml
apiVersion: batch/v1
kind: Job
metadata: { name: kube-bench }
spec:
  template:
    spec:
      nodeSelector: { node-purpose: cis-benchmark }   # the AL2023 node label
      hostPID: true
      containers:
      - name: kube-bench
        image: aquasec/kube-bench:latest
        command: ["kube-bench","run","--targets","node","--benchmark","eks-1.2.0"]
        volumeMounts: [ /var/lib/kubelet, /etc/kubernetes, /etc/systemd ... (host mounts) ]
      restartPolicy: Never
      volumes: [ hostPath mounts for the above ]
```
Then read results: `kubectl logs job/kube-bench`. Output is per-control PASS/FAIL/WARN with
remediation text; export/store it as compliance evidence.

Alternatively run kube-bench **directly on the node** via **SSM Session Manager** (the
`kube-bench/` node role includes `AmazonSSMManagedInstanceCore`).

---

## 4. Interpreting results & remediation

- **FAIL** — a CIS control not met; apply the remediation (e.g. tighten a file permission,
  set a kubelet flag). On EKS many node controls are already handled by the EKS-optimized
  AMI.
- **WARN** — manual verification needed (control can't be auto-checked).
- **INFO** — informational.
- Track findings over time; feed into **AWS Security Hub** (which has CIS EKS standards) and
  your audit/compliance reporting.

---

## 5. Best practices

- Treat CIS benchmark results as **continuous** compliance, not one-off — re-run on node AMI
  updates and cluster upgrades.
- Prefer **immutable, managed nodes** (Auto Mode / Bottlerocket) which eliminate many
  node-hardening findings by design.
- Centralize evidence in **Security Hub / Audit Manager**; automate re-scans in CI.
- Combine with the other domains: CIS covers config hardening; pair with runtime detection
  (GuardDuty, cmd 28), admission policy (PSA/Gatekeeper, cmd 23–24), and least-privilege IAM.

---

## 6. Relation to the rest of the workshop

- Maps to the [`kube-bench/`](../kube-bench/) Terraform (temporary AL2023 node group).
- The Auto Mode / Bottlerocket constraint ties back to why `eks-auto` uses managed nodes and
  why other modules (e.g. IRSA `NoCredentials`, Network Policy node agent) behaved the way
  they did — the data plane is AWS-managed and locked down.
