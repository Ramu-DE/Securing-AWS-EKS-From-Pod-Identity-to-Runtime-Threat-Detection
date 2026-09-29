# Command 25: Kubernetes Network Policies on EKS Auto Mode (deny-all → allow client-one)

```bash
# Demo: demo-app (nginx) + client-one/client-two in netpol-demo, another-client-one in another-ns
# 0) Baseline: no policy -> all clients reach demo-app

# 1) ENABLE the Network Policy Controller (REQUIRED on Auto Mode)
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata: { name: amazon-vpc-cni, namespace: kube-system }
data: { enable-network-policy-controller: "true" }
EOF

# 2) Set the node default posture to DefaultDeny (isolate by default)
kubectl patch nodeclass default --type merge \
  -p '{"spec":{"networkPolicy":"DefaultDeny","networkPolicyEventLogs":"Enabled"}}'
# -> Auto Mode rolls fresh node(s); the eBPF agent enables enforcement at node start

# 3) Allow ingress to demo-app ONLY from client-one
kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-from-client-one, namespace: netpol-demo }
spec:
  podSelector: { matchLabels: { app: demo-app } }
  policyTypes: ["Ingress"]
  ingress:
  - from:
    - podSelector: { matchLabels: { app: client-one } }
EOF
```

> Concept background: [`modules-docs/network-policies.md`](../../modules-docs/network-policies.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Enforce L3/L4 pod isolation: switch the cluster to deny-by-default and allow **only** client-one → demo-app, blocking everyone else. |
| 2 | **What happens in Kubernetes** | Enables the VPC CNI Network Policy Controller (ConfigMap), sets NodeClass `DefaultDeny` (rolls fresh nodes), and applies a NetworkPolicy. The controller generates a **PolicyEndpoint**; the eBPF node agent programs the allow. Result: client-one reaches demo-app, client-two/another-ns are blocked. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (API server, VPC CNI Network Policy Controller, eBPF node agent — all service-managed on Auto Mode). Enforcement is in-cluster (eBPF); no external AWS API per request. |

---

## 1. In one sentence

Turn the cluster's pod network deny-by-default and prove a single allow-rule lets only
client-one talk to demo-app.

---

## 2. Actual execution in this environment (including a real troubleshooting arc)

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`).

### 2a. Baseline — no policy, everything reachable
```
[netpol-demo/client-one]          -> demo-app: REACHABLE
[netpol-demo/client-two]          -> demo-app: REACHABLE
[another-ns/another-client-one]   -> demo-app: REACHABLE
```

### 2b. First attempt: applied a deny-all NetworkPolicy → **no effect**
All clients still reachable, and **no PolicyEndpoint** was generated. Investigation showed:
- NodeClass `networkPolicy: DefaultAllow` (the Auto Mode default).
- **No `amazon-vpc-cni` ConfigMap** → the **Network Policy Controller was not enabled**.

### 2c. Root cause & fix (two requirements)
1. **Enabled the controller** via the `amazon-vpc-cni` ConfigMap
   (`enable-network-policy-controller: "true"`). → a **PolicyEndpoint**
   (`allow-from-client-one-smnpk`) was then generated. ✅
2. **NodeClass → `DefaultDeny`** (verified enum values `DefaultAllow|DefaultDeny`). Under
   DefaultDeny, all traffic was correctly **BLOCKED** (proving enforcement is active).
3. **Node recycle required:** allow-rules still weren't programmed because the running
   nodes **predated** the ConfigMap — their eBPF agents started without the controller. I
   deleted the NodeClaim; Auto Mode launched a **fresh node** (`i-0504...`) whose agent
   started with the controller enabled.

### 2d. DEFINITIVE result — only client-one allowed ✅
```
PolicyEndpoint allow-from-client-one-smnpk  allowFrom=10.254.40.180   (= client-one's IP)

[netpol-demo/client-one] -> demo-app: REACHABLE
[netpol-demo/client-two] -> demo-app: BLOCKED
```
This matches the workshop reference image `sc4-allow-from-client-one` exactly: the PolicyEndpoint
targets the demo-app pod and permits **only** client-one's pod IP; client-two (and any
other-namespace client) is denied by the default-deny posture.

---

## 3. Lessons (documented so you don't repeat the troubleshooting)

- On **EKS Auto Mode**, NetworkPolicy enforcement needs **BOTH**: the
  `amazon-vpc-cni` ConfigMap (`enable-network-policy-controller: "true"`) **and** a
  suitable NodeClass posture (`DefaultDeny` for deny-by-default).
- The eBPF node agent reads the controller-enabled state **at node start** — enable it
  **before** nodes launch, or **recycle nodes** afterward. A present PolicyEndpoint with the
  correct `allowFrom` CIDR but no enforcement = stale node agent.
- Verify with `kubectl get policyendpoints -A` and by checking the `allowFrom` CIDR equals
  the intended source pod's IP.

---

## 4. Cleanup / handy commands

```bash
kubectl get policyendpoints -A -o wide
kubectl -n netpol-demo get networkpolicy
# revert node posture (also a node roll):
kubectl patch nodeclass default --type merge -p '{"spec":{"networkPolicy":"DefaultAllow"}}'
kubectl delete ns netpol-demo another-ns
kubectl -n kube-system delete cm amazon-vpc-cni   # disable the controller
```
