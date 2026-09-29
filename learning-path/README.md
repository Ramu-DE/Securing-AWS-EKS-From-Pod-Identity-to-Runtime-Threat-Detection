# Learning Path — Study the workshop module by module

This folder contains a **structured learning path** as Excel workbooks so you can learn each
module in order and track your progress.

## Files

| File | What it is |
|------|-----------|
| **`00-EKS-Security-Learning-Path.xlsx`** | **Master workbook** — start here. 3 sheets: **Learning Path** (recommended order + goals), **Progress Tracker** (mark each module Done), **Key Concepts** (one-line takeaway + AWS services per module). |
| `00-Orientation-&-EKS-Auth-Basics.xlsx` … `10-Regulatory-Compliance.xlsx` | **Per-module workbooks** — one per module. 3 sheets each: **Overview** (goal / why / key takeaway / AWS services / linked command logs + concept docs), **Steps** (the hands-on steps with a Done? column), **Self-Check** (6 questions to test understanding, with space for your answers). |

## Recommended order (Foundation → Core → Advanced)

| # | Module | Level | Maps to command logs |
|---|--------|-------|----------------------|
| 00 | Orientation & EKS Auth Basics | Foundation | 01–04 |
| 01 | IAM Groups & Roles (aws-auth) + RBAC | Core | 05–12 |
| 02 | IRSA | Core | 13–15 |
| 03 | EKS Pod Identity (+ ABAC) | Core | 16, 17, 20 |
| 04 | EKS Access Entries & OIDC IdP | Core | 18, 19, 21, 22 |
| 05 | Pod Security (PSS/PSA) + OPA/Gatekeeper | Core | 23, 24 |
| 06 | Network Policies | Advanced | 25 |
| 07 | Secrets Manager CSI | Advanced | 26 |
| 08 | Image Security (ECR / Inspector / Signing) | Advanced | 27 |
| 09 | Detective Controls | Advanced | 28 |
| 10 | Regulatory Compliance (kube-bench) + Network (Lattice/mTLS) | Advanced | concept |

## How to use

1. Open the **master workbook** and read the **Learning Path** sheet.
2. For each module, open its **per-module workbook**:
   - Read **Overview** → do the **Steps** (open the matching files in
     [`../command-log/commands/`](../command-log/commands) for exact commands + real output) →
     answer the **Self-Check** questions in your own words.
   - The **why** behind each step is in the matching file in
     [`../modules-docs/`](../modules-docs).
3. Mark the module **Done** in the master workbook's **Progress Tracker** sheet.

> The Excel files are plain OOXML (`.xlsx`) and open in Microsoft Excel, LibreOffice Calc,
> Google Sheets, or Numbers.
