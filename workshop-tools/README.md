# Workshop Tools Reference

This document describes the command-line tools, utilities, and shortcuts that come
pre-installed in the EKS Security Immersion Day workshop environment (the IDE). Each
entry explains **what the tool is** and **why we use it** during the labs.

---

## Kubernetes Tools

### `kubectl` — Kubernetes command-line tool
The Kubernetes command-line tool, `kubectl`, allows us to run commands against
Kubernetes clusters. We can use `kubectl` to deploy applications, inspect and manage
cluster resources, and view logs.

### `helm` — Kubernetes package manager
Helm helps us manage Kubernetes applications. Helm Charts help us define, install, and
upgrade even the most complex Kubernetes application.

### `k9s` — Terminal UI for Kubernetes
K9s is a terminal-based UI to interact with Kubernetes clusters. The aim of this project
is to make it easier to navigate, observe, and manage deployed applications. K9s
continually watches Kubernetes for changes and offers subsequent commands to interact
with observed resources.

### `eks-node-viewer` — Node usage visualizer
`eks-node-viewer` is a tool for visualizing dynamic node usage within a cluster. It was
originally developed as an internal tool at AWS for demonstrating consolidation with
Karpenter. It displays the scheduled pod resource requests vs. the allocatable capacity
on the node. It does **not** look at the actual pod resource usage.

---

## Kubernetes Context & Namespace Switching

### `kns` — Fast namespace switching
`kns` is a very small shell script that utilizes `fzf` to switch between Kubernetes
namespaces fast.

### `kctx` (kubectx) — Fast context switching
`kubectx` is a tool to switch between contexts (clusters) on `kubectl` faster. A
Kubernetes context is a group of access parameters that define which cluster we're
interacting with, which user we're using, and which namespace we're working in. It's
helpful if we need to access different clusters for different purposes, or if we want to
limit our access to certain parts of a cluster.

---

## Container Tools

### `docker` — Container runtime and CLI
The container runtime and CLI, used in the Image Security module to build, tag, and push
container images to Amazon ECR.

---

## AWS Tools

### AWS CLI version 2
The official command-line interface for interacting with AWS services (EKS, ECR, IAM,
CloudWatch, Inspector, and more) throughout the workshop.

### IAM role
An AWS Identity and Access Management (IAM) role provides the permissions the workshop
environment uses to authenticate and interact with AWS services and the EKS cluster.

---

## Text & Data Processing Utilities

### `jq` — JSON processor
A lightweight command-line JSON processor, used to parse, filter, and transform JSON
output (for example, from AWS CLI responses).

### `yq` — YAML processor
A command-line YAML processor, used to read and manipulate YAML files such as Kubernetes
manifests.

### `envsubst` — Environment variable substitution
The `envsubst` command is used to substitute environment variables in text (for example,
templating placeholders in manifests before applying them).

### `bash-completion`
Bash completion is a bash function that allows us to auto-complete commands or arguments
by typing partial commands or arguments, then pressing the `[Tab]` key.

---

## Shell Aliases

A set of shortcuts is pre-configured to speed up common commands. Type `alias` in the
terminal to see them all.

| Alias | Expands to / Purpose |
|-------|----------------------|
| `k`   | `kubectl` — shorthand for the Kubernetes CLI |
| `kgn` | Get nodes — list cluster nodes (`kubectl get nodes`) |
| `kgp` | Get pods — list pods (`kubectl get pods`) |
| `tfi` | Terraform init |
| `tfp` | Terraform plan |
| `tfy` | Terraform apply (auto-approve) |

> Tip: run `alias` at any time to see the full, current list of shortcuts in your
> environment.
