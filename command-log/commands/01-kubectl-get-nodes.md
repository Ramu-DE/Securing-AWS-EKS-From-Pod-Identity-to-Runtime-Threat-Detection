# Command 01: `kubectl get nodes`

```bash
kubectl get nodes
```

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | List the worker machines (nodes) in the cluster and confirm they are healthy. A basic connectivity/sanity check. |
| 2 | **What happens in Kubernetes** | A **read-only** query to the Kubernetes API server for `Node` objects. Nothing is created or changed. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (the managed Kubernetes control plane serving the API). Authentication also quietly uses **AWS STS** via the token flow, but the command itself targets the EKS API server. No node/EC2 changes. |

---

## 1. In one sentence

This command asks your Kubernetes cluster: **"Show me the list of worker machines
(nodes) you are running on, and are they healthy?"**

---

## 2. Background concepts (for beginners)

Before the command makes sense, here are the key ideas:

- **Kubernetes** is a system that runs and manages your applications (packaged as
  containers) across a group of computers. Instead of you logging into each server,
  Kubernetes decides where things run.

- **Cluster** = the whole Kubernetes system: a *control plane* (the "brain" that makes
  decisions) plus a set of *nodes* (the "muscle" that actually runs your app containers).

- **Node** = a single machine (in AWS EKS, an EC2 virtual machine) that runs your
  workloads. Your application containers live inside **pods**, and pods run **on nodes**.

- **`kubectl`** (pronounced "cube-control" or "cube-cuttle") = the command-line tool you
  use to talk to a Kubernetes cluster. Every `kubectl` command sends a request to the
  cluster's control plane (the **API server**) and prints back the answer.

So `kubectl get nodes` is simply: use `kubectl` to **get** (list) the **nodes**.

---

## 3. Breaking the command down piece by piece

| Piece | Meaning |
|-------|---------|
| `kubectl` | The tool that talks to the Kubernetes cluster. |
| `get` | The **verb** — "retrieve / list" a resource. (Other verbs: `describe`, `delete`, `apply`.) |
| `nodes` | The **resource type** you want to list — the worker machines. |

Put together: **"kubectl, please list the nodes."**

---

## 4. How it works, step by step

1. You type `kubectl get nodes` and press Enter.
2. `kubectl` reads your **kubeconfig** file (usually at `~/.kube/config`). This file tells
   `kubectl` *which* cluster to contact and *how to authenticate* (prove who you are).
   In this workshop, the kubeconfig was set up for you by `aws eks update-kubeconfig`.
3. `kubectl` sends an HTTPS request to the cluster's **API server** asking for the list
   of Node objects.
4. The API server checks your identity/permissions, reads the current node list from its
   internal database (**etcd**), and sends the data back.
5. `kubectl` formats that data into the neat table you see in the terminal.

---

## 5. Why we run it in the workshop

- **Confirm the cluster is up and reachable.** If this command returns nodes, your
  `kubectl` is correctly connected and authenticated to the cluster. It's a great first
  "sanity check."
- **See the compute available** to run workloads before we deploy anything.
- **Check node health** — the `STATUS` column should say `Ready`.

> Note on **EKS Auto Mode**: the main workshop cluster (`eks-auto`) uses EKS Auto Mode,
> where AWS manages the nodes for you. You may see **zero nodes** at first if nothing is
> scheduled yet — Auto Mode launches nodes on demand when workloads need them. That is
> normal, not an error.

---

## 6. Example output and how to read it

```
NAME                                          STATUS   ROLES    AGE     VERSION
i-0abc123def4567890.ec2.internal              Ready    <none>   10m     v1.31.0-eks-abcdef
i-0fed987cba6543210.ec2.internal              Ready    <none>   9m      v1.31.0-eks-abcdef
```

| Column | What it tells you |
|--------|-------------------|
| `NAME` | The node's name (for EKS nodes this is usually the EC2 instance ID / DNS name). |
| `STATUS` | Health of the node. `Ready` = healthy and able to run pods. `NotReady` = a problem. |
| `ROLES` | The node's role. `<none>` is normal for worker nodes (they don't run the control plane). |
| `AGE` | How long the node has existed. |
| `VERSION` | The version of `kubelet` (the Kubernetes agent) running on the node — closely tracks the cluster's Kubernetes version. |

---

## 7. Handy variations

```bash
kubectl get nodes -o wide      # More detail: internal/external IP, OS, kernel, container runtime
kubectl get nodes --watch      # Live-update the list as nodes change (Ctrl+C to stop)
kubectl describe node <NAME>   # Deep detail about one node: capacity, conditions, pods on it
kubectl get nodes -o yaml      # Full raw definition in YAML
```

There is also a workshop alias for this:

```bash
kgn      # shorthand for: kubectl get nodes
```

---

## 8. Common issues (beginner troubleshooting)

- **`The connection to the server ... was refused`** → `kubectl` can't reach the cluster.
  The kubeconfig may be missing or pointing at the wrong cluster. Re-run
  `aws eks update-kubeconfig --name eks-auto`.
- **`error: You must be logged in to the server (Unauthorized)`** → Your identity isn't
  allowed. Check your AWS credentials / IAM role.
- **No nodes listed** → On EKS Auto Mode this can be normal (see the note in section 5).

---

## 9. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, region `us-west-2`, cluster `eks-auto`)

```bash
$ kubectl get nodes
No resources found
```

**Result:** exit status `0` (success). The command connected and authenticated to the
cluster correctly — it just found **no nodes**.

**Why "No resources found" here is expected:** the `eks-auto` cluster runs in **EKS Auto
Mode**. AWS launches nodes on demand only when there are workloads (pods) that need to be
scheduled. At this point in the workshop nothing has been deployed yet, so there are zero
nodes. This is **normal, not an error** — confirmed by the exit status of `0`. Once we
deploy an application later, re-running `kubectl get nodes` will show one or more `Ready`
nodes that Auto Mode created.
