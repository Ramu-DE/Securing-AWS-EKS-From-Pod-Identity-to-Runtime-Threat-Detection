# Command 22: Inspect OIDC identity-provider configuration (read-only)

```bash
# User-authentication OIDC IdP associations on the cluster (Cognito/Okta/etc.)
aws eks list-identity-provider-configs --cluster-name eks-auto

# The cluster's OWN OIDC issuer (used by IRSA — a different concept)
aws eks describe-cluster --name eks-auto --query 'cluster.identity.oidc.issuer' --output text
```

> Concept background: [`modules-docs/oidc-identity-provider-authentication.md`](../../modules-docs/oidc-identity-provider-authentication.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Check whether a **user-authentication OIDC identity provider** (e.g. Cognito) is associated with the cluster, and contrast it with the cluster's own IRSA OIDC issuer. |
| 2 | **What happens in Kubernetes** | **Nothing.** Read-only EKS API queries; no cluster object changes. |
| 3 | **Which AWS service is called/used** | **Amazon EKS** only (`eks:ListIdentityProviderConfigs`, `eks:DescribeCluster`). |

---

## 1. Why this module is mostly concept-only here

Associating a **user-auth OIDC IdP** requires an external IdP with real users/groups (the
workshop uses an **Amazon Cognito** user pool created via the console) plus the
`associate-identity-provider-config` step. That external setup isn't scripted in this
environment, so this module is documented as a **concept** (see the module doc) and we run
only the safe read-only inspection here.

---

## 2. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`).

```
$ aws eks list-identity-provider-configs --cluster-name eks-auto
{ "identityProviderConfigs": [] }

$ aws eks describe-cluster --name eks-auto --query 'cluster.identity.oidc.issuer' --output text
https://oidc.eks.us-west-2.amazonaws.com/id/5CC109EF2CCB404415FA350577E27AF5
```

**Reading the result — the crucial distinction:**
- **No user-auth OIDC IdP is associated** (`identityProviderConfigs: []`). So no
  Cognito/Okta users can `kubectl` into this cluster yet — that's the association step this
  module would add.
- The cluster **does** have an OIDC **issuer** (`.../id/5CC1...`), but that is the **IRSA**
  issuer (pods → AWS), *not* a user-authentication IdP. Same technology (OIDC/JWT), opposite
  direction. Don't conflate them.

This matches the module doc's "two OIDCs in EKS" warning with concrete evidence.

---

## 3. To actually associate one (reference)

```bash
aws eks associate-identity-provider-config --cluster-name eks-auto \
  --oidc identityProviderConfigName=cognito,issuerUrl=https://cognito-idp.<region>.amazonaws.com/<pool>,\
clientId=<app-client-id>,usernameClaim=email,groupsClaim=cognito:groups
# then bind the group claim (e.g. "secret-reader") with a RoleBinding/ClusterRoleBinding.
```
See the full flow, group-claim example, and audit notes in
[`modules-docs/oidc-identity-provider-authentication.md`](../../modules-docs/oidc-identity-provider-authentication.md).

---

## 4. Handy related commands

```bash
aws eks list-identity-provider-configs --cluster-name eks-auto
aws eks describe-identity-provider-config --cluster-name eks-auto \
  --identity-provider-config type=oidc,name=<name>
aws eks disassociate-identity-provider-config --cluster-name eks-auto \
  --identity-provider-config type=oidc,name=<name>
```
