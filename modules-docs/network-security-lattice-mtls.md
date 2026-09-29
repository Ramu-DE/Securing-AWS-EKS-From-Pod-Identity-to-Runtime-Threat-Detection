# Module: Network Security — VPC Lattice service access & mTLS with ALB

Two application-layer network-security patterns beyond L3/L4 NetworkPolicies (cmd 25):
**VPC Lattice** for secure cross-VPC/cross-cluster service access, and **mTLS with an
Application Load Balancer** for mutual transport authentication. Both are **concept +
provisioning-flagged** here (they require additional infra with cost).

> Preventive layering: NetworkPolicies (cmd 25) = pod-level L3/L4 east-west; **VPC Lattice**
> = L7 service-to-service across network boundaries; **mTLS** = cryptographic client+server
> identity at the transport layer.

---

## Part A — VPC Lattice service access

### What it is
**Amazon VPC Lattice** is an application-layer (L7) networking service that connects,
secures, and monitors service-to-service communication **across VPCs and accounts** without
peering, NAT, or overlapping-CIDR concerns. Services join a **service network**; Lattice
handles routing, and **IAM auth policies** authorize calls.

### Why for EKS
- Connect services in **different clusters/VPCs** (our Terraform has a second cluster
  `eks-auto-2` for exactly this) without VPC peering — CIDRs may even overlap.
- Enforce **IAM-based auth policies** on service access (`usecase2-iam-auth-flow.svg`) —
  identity-aware, not just IP-based.
- Managed via the **AWS Gateway API Controller**, so you define Lattice resources using
  Kubernetes **Gateway API** objects (`Gateway`, `HTTPRoute`) that map to Lattice
  service networks/services/target groups (`vpc-lattice-to-k8s-objects.png`).

### Flow (high level)
```
Client pod (VPC A / cluster 1)
   → VPC Lattice service network  (auth policy: IAM SigV4 authorization)
   → target service (VPC B / cluster 2)   — no peering, L7 routing, per-service authZ
```

### Terraform in this repo
- [`eks-auto-2/`](../eks-auto-2/) provisions the **second Auto Mode cluster** (its own VPC,
  overlapping CIDR is fine — Lattice connects at L7). VPC Lattice then links the two.

> ⚠️ **Heavy provisioning — flagged, not applied.** Standing up VPC Lattice needs the
> second cluster + Gateway API Controller + Lattice service network/services + Route53/ACM
> for custom domains (the `acm-cert.png`, `route53-*` images). Cost + blast radius →
> document; provision only with explicit approval and `terraform apply` in `eks-auto-2/`.

---

## Part B — mTLS with Application Load Balancer

### TLS vs mTLS (from `mtls_vs_tls.png`)
- **TLS**: the **client** verifies the **server**'s certificate (one-way).
- **mTLS (mutual TLS)**: **both** sides present certificates — the ALB also verifies the
  **client's** certificate against a **trust store**. This authenticates *who the caller
  is* at the transport layer, before any application logic.

### How it works on EKS (from `MTLS-Kubernetes-Traffic-Flow.png` / `system_arch.png`)
```
Client (with client cert) ──mTLS──► ALB (mTLS listener + TrustStore in S3)
   → ALB verifies client cert against the trust store (CA bundle)
   → forwards to the EKS Ingress/Service (demo app) only if the client cert is trusted
```
- The **ALB mTLS listener** is configured with a **trust store** (a CA bundle in **S3**)
  — `s3-truststore.png`, `ec2-truststore.png`, `mtls-listeners.png`.
- Modes: **verify** (reject untrusted clients) vs **passthrough**. `mtls-on.png` /
  `mtls-off.png` show the before/after.
- The **AWS Load Balancer Controller** provisions the ALB from Kubernetes `Ingress`.

### Client/server certificates
- A private CA issues the **server** cert (for the ALB domain) and **client** certs.
- The workshop uses **ACM / ACM Private CA (ACM-PCA)** to issue/manage certificates
  (`acm-pca1.png`).

> ⚠️ **ACM Private CA cost — flagged, not provisioned.** **ACM-PCA has a significant
> monthly cost** per CA plus per-certificate charges. The ALB, trust store (S3), and
> ACM-PCA are documented here; provision only with explicit approval.

---

## Best practices

- Use **VPC Lattice** to avoid broad VPC peering; scope access with **IAM auth policies**
  per service (least privilege, identity-aware).
- Use **mTLS** for zero-trust transport identity where clients must prove who they are
  (partner APIs, sensitive internal services); keep the **trust store** tight and rotate
  client certs.
- Layer these over **NetworkPolicies** (cmd 25) — L3/L4 isolation + L7 identity-aware
  access + transport mutual-auth = defense in depth.
- Prefer **short-lived certs** and automate rotation (ACM/ACM-PCA); monitor Lattice access
  logs and ALB access logs (ties into Detective Controls, cmd 28).

---

## Relation to the rest of the workshop

- Completes the **Network Security** domain alongside **Network Policies** (cmd 25).
- Auth policies (Lattice) reuse **IAM** identity concepts from the IAM domain; mTLS
  complements app-layer authZ with transport-layer authN.
- Both are provisioning-heavy and are intentionally documented (not applied) to avoid cost
  and cluster churn — mirroring the workshop's own "flag before provisioning" guidance.
