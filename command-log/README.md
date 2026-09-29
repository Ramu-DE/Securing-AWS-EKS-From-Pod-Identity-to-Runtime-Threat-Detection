# Command Log

> 📐 **New here? Start with [`../ARCHITECTURE.md`](../ARCHITECTURE.md)** — the top-level map
> of all modules, identity chains, and how everything fits together.

This folder is a running log of **every command we execute** during the EKS Security
Immersion Day workshop. It is written for **beginners** — each entry explains:

- **What** the command does
- **Why** we run it (its purpose in the workshop)
- **How** it works (broken down piece by piece)
- **What the output looks like** and how to read it

Each command gets its own numbered file inside the [`commands/`](./commands) folder so
the log stays easy to follow and easy to push to GitHub later.

---

## The 3-point summary (every entry has this)

Because understanding *where* each command acts is essential, **every** command entry
includes a **"Quick Summary"** box near the top answering three questions:

1. **Purpose of the command** — what goal it accomplishes.
2. **What happens in Kubernetes** — the effect on the cluster / Kubernetes objects (or
   "nothing — this is a local/AWS-only command").
3. **Which AWS service is called/used** — the specific AWS service(s) involved (e.g. STS,
   EKS, ECR, IAM) or "none — purely local/Kubernetes."

---

## Index

| # | Command | Description | Log file |
|---|---------|-------------|----------|
| 01 | `kubectl get nodes` | List the worker nodes in the cluster | [01-kubectl-get-nodes.md](./commands/01-kubectl-get-nodes.md) |
| 02 | `echo "$AWS_REGION"` etc. | Print key environment variables (region, account, cluster) | [02-echo-environment-variables.md](./commands/02-echo-environment-variables.md) |
| 03 | `ls artifacts/` | List a folder's contents (relative vs absolute paths) | [03-ls-artifacts.md](./commands/03-ls-artifacts.md) |
| 04 | `aws eks get-token ...` (decode) | Generate & decode the EKS auth token (IAM → cluster access) | [04-eks-get-token-decode.md](./commands/04-eks-get-token-decode.md) |
| 05 | `aws sts get-caller-identity` + `aws-auth` check | Find the IDE's IAM role and check it against the aws-auth ConfigMap | [05-check-ide-role-in-aws-auth.md](./commands/05-check-ide-role-in-aws-auth.md) |
| 06 | `aws iam create-role` x3 | Create 3 least-privileged IAM roles (k8sAdmin/k8sDev/k8sInteg) | [06-create-iam-roles.md](./commands/06-create-iam-roles.md) |
| 07 | `aws iam create-group` + `put-group-policy` x3 | Create 3 IAM groups + assume-role policies | [07-create-iam-groups.md](./commands/07-create-iam-groups.md) |
| 08 | `aws iam create-user` + `add-user-to-group` + `create-access-key` | Create 3 IAM users, add to groups, mint access keys | [08-create-iam-users.md](./commands/08-create-iam-users.md) |
| 09 | `kubectl create namespace` + `kubectl apply` (Role/RoleBinding) | Create K8s namespaces + RBAC Roles/RoleBindings | [09-k8s-rbac-namespaces-roles.md](./commands/09-k8s-rbac-namespaces-roles.md) |
| 10 | `eksctl create iamidentitymapping` x3 | Map IAM roles into the cluster via aws-auth ConfigMap | [10-configure-aws-auth-configmap.md](./commands/10-configure-aws-auth-configmap.md) |
| 11 | AWS CLI profiles + per-persona kubeconfig tests | Test scoped EKS access (dev/integ/admin) end to end | [11-test-eks-access-profiles.md](./commands/11-test-eks-access-profiles.md) |
| 12 | `eksctl create iamidentitymapping` (console role) | Grant AWS Console access to the cluster (optional) | [12-console-access-mapping.md](./commands/12-console-access-mapping.md) |
| 13 | `kubectl apply` (test pod) + `kubectl logs` | IRSA motivation: pod with no identity fails `NoCredentials` | [13-irsa-nocredentials-demo.md](./commands/13-irsa-nocredentials-demo.md) |
| 14 | `kubectl get sa` + `exec cat token` | Inspect the projected Service Account OIDC token | [14-projected-service-account-token.md](./commands/14-projected-service-account-token.md) |
| 15 | `eksctl create iamserviceaccount` + test pods | Enable IRSA end to end (OIDC → SA+role → working S3 access) | [15-enable-irsa.md](./commands/15-enable-irsa.md) |
| 16 | `aws eks create-pod-identity-association` + test | Enable EKS Pod Identity end to end | [16-enable-eks-pod-identity.md](./commands/16-enable-eks-pod-identity.md) |
| 17 | `s3 mb` + delete/recreate pod + `s3 ls` | Test EKS Pod Identity (creds injected at pod creation) | [17-test-eks-pod-identity.md](./commands/17-test-eks-pod-identity.md) |
| 18 | `aws eks list-access-policies` | List EKS access policies + inspect current access entries | [18-list-access-policies.md](./commands/18-list-access-policies.md) |
| 19 | `aws eks describe-cluster` (accessConfig) | Auth modes: inspect only (one-way switch to API **not** run) | [19-switching-authentication-modes.md](./commands/19-switching-authentication-modes.md) |
| 20 | trust-policy + S3-policy session-tag conditions | Pod Identity access-control use cases (cluster/namespace/object ABAC) | [20-pod-identity-access-control-usecases.md](./commands/20-pod-identity-access-control-usecases.md) |
| 21 | `aws eks create-access-entry` + `associate-access-policy` | Create access entries + scoped policies for 3 personas | [21-create-access-entries-policies.md](./commands/21-create-access-entries-policies.md) |
| 22 | `aws eks list-identity-provider-configs` | Inspect OIDC identity-provider config (read-only) | [22-oidc-identity-provider-inspect.md](./commands/22-oidc-identity-provider-inspect.md) |
| 23 | `kubectl label ns pod-security.kubernetes.io/*` | Pod Security Admission: enforce/warn PSS levels demo | [23-pod-security-pss-psa.md](./commands/23-pod-security-pss-psa.md) |
| 24 | `helm install gatekeeper` + ConstraintTemplate/Constraint | OPA/Gatekeeper: custom admission policy (deny privileged) | [24-opa-gatekeeper.md](./commands/24-opa-gatekeeper.md) |
| 25 | `enable-network-policy-controller` + NodeClass DefaultDeny + NetworkPolicy | Network Policies: deny-all → allow client-one (eBPF) | [25-network-policies.md](./commands/25-network-policies.md) |
| 26 | Secrets Store CSI + ASCP + IRSA + SecretProviderClass | Mount an AWS Secrets Manager secret into a pod | [26-secrets-manager-csi.md](./commands/26-secrets-manager-csi.md) |
| 27 | `aws ecr create-repository` + repo/lifecycle policies | ECR security controls (scan-on-push, immutable, policies) | [27-ecr-security-controls.md](./commands/27-ecr-security-controls.md) |

---

## Related concept docs

- [`modules-docs/iam-and-eks-access.md`](../modules-docs/iam-and-eks-access.md) — IAM
  authentication/authorization and the three EKS cluster-access mechanisms.
- [`modules-docs/iam-groups-and-roles-aws-auth.md`](../modules-docs/iam-groups-and-roles-aws-auth.md)
  — the legacy `aws-auth` ConfigMap, cluster creator admin, and RBAC basics.
- [`modules-docs/kubernetes-authentication-rbac.md`](../modules-docs/kubernetes-authentication-rbac.md)
  — Kubernetes RBAC: Roles, ClusterRoles, Bindings, Namespaces, and mapping to IAM groups.
- [`modules-docs/iam-rbac-module-conclusion.md`](../modules-docs/iam-rbac-module-conclusion.md)
  — **Module conclusion**: the full IAM Groups + RBAC access chain, why it works, and security caveats.
- [`modules-docs/irsa.md`](../modules-docs/irsa.md) — IAM Roles for Service Accounts:
  the pod-identity problem, IRSA vs. Pod Identity, OIDC machinery, and benefits.
- [`modules-docs/irsa-complete-flow.md`](../modules-docs/irsa-complete-flow.md) —
  **IRSA complete flow**: walkthrough of all 5 IRSA diagrams (runtime flow, trust policy, permissions, OIDC provider, RBAC-vs-IAM).
- [`modules-docs/eks-pod-identity.md`](../modules-docs/eks-pod-identity.md) — **EKS Pod
  Identity**: the EKS-native alternative to IRSA, its workflow, and a side-by-side comparison.
- [`modules-docs/eks-access-management-controls.md`](../modules-docs/eks-access-management-controls.md)
  — **EKS access entries**: the modern replacement for aws-auth, access policies, authorizers, and auth modes.
- [`modules-docs/access-entries-persona-plan.md`](../modules-docs/access-entries-persona-plan.md)
  — **Access-entries persona plan**: the 3 personas (ClusterAdmin/TeamADev/TeamATest) and which access policy each gets.
- [`modules-docs/oidc-identity-provider-authentication.md`](../modules-docs/oidc-identity-provider-authentication.md)
  — **OIDC IdP authentication**: authenticating human users via Cognito/Okta, group claims, RBAC, and audit.
- [`modules-docs/pod-security-pss-psa.md`](../modules-docs/pod-security-pss-psa.md) —
  **Pod Security (PSS/PSA)**: the 3 standards levels, 3 admission modes, the Deployment UX gotcha, and best practices.
- [`modules-docs/opa-gatekeeper.md`](../modules-docs/opa-gatekeeper.md) — **OPA/Gatekeeper**:
  policy-based admission control (ConstraintTemplate + Constraint), Rego, and PSA-vs-Gatekeeper.
- [`modules-docs/network-policies.md`](../modules-docs/network-policies.md) — **Network
  Policies**: L3/L4 pod isolation, VPC CNI controller + eBPF, policy evaluation order, and Auto Mode enablement.
- [`modules-docs/secrets-manager-csi.md`](../modules-docs/secrets-manager-csi.md) —
  **Secrets Manager CSI**: mount secrets as files via the Secrets Store CSI driver + ASCP + IRSA.
- [`modules-docs/image-security.md`](../modules-docs/image-security.md) — **Image Security**:
  ECR controls, Inspector CVE scanning, DevSecOps pipeline gate, and image signing (Signer/Notation/Kyverno).
- [`modules-docs/network-security-lattice-mtls.md`](../modules-docs/network-security-lattice-mtls.md)
  — **Network Security**: VPC Lattice (L7 cross-VPC/cluster access) and mTLS with ALB (provisioning flagged).
- [`modules-docs/detective-controls.md`](../modules-docs/detective-controls.md) —
  **Detective Controls**: GuardDuty EKS Protection, EKS audit logs + Log Insights, CloudTrail.
- [`modules-docs/regulatory-compliance-kube-bench.md`](../modules-docs/regulatory-compliance-kube-bench.md)
  — **Regulatory Compliance**: CIS Benchmark with kube-bench (Auto Mode/Bottlerocket constraint, kube-bench/ terraform).

---

## How to read this log

- Commands are logged in the **order we run them**.
- Every new command appends a row to the index table above and adds a file under
  `commands/`.
- Terms that may be new to a beginner are explained inline the first time they appear.
