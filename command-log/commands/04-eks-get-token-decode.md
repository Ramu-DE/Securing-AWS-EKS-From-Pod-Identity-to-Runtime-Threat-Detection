# Command 04: Generate and decode an EKS authentication token

```bash
TOKEN_DATA=$(aws eks get-token --cluster-name eks-auto | jq -r '.status.token')
echo $TOKEN_DATA
IFS='.' read header payload signature <<< "$TOKEN_DATA"
echo "$payload" | fold -w 4 | sed '$ d' | tr -d '\n' | base64 --decode
```

> Concept background for this command lives in
> [`modules-docs/iam-and-eks-access.md`](../../modules-docs/iam-and-eks-access.md).

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Generate the bearer token `kubectl` uses to authenticate to EKS, then decode it to reveal it is a pre-signed STS `GetCallerIdentity` URL. |
| 2 | **What happens in Kubernetes** | **Nothing directly.** No request is sent to the cluster here — we only *mint and inspect* the token locally. (The token would later be sent to the EKS API server on a real `kubectl` call.) |
| 3 | **Which AWS service is called/used** | **Amazon EKS** (`aws eks get-token` builds the token) and, embedded inside the token, **AWS STS** (`sts:GetCallerIdentity`). The decode steps (`jq`, `base64`, etc.) are local. |

---

## 1. In one sentence

These four commands **generate the bearer token that `kubectl` uses to prove your
identity to the EKS cluster**, then **decode the readable part of it** to reveal that it
is really a pre-signed AWS STS "who am I?" URL.

---

## 2. Background concepts (for beginners)

- **Bearer token** = a string that says "whoever holds (bears) this token is allowed in."
  `kubectl` sends one to the cluster on every request to prove who you are.
- **STS (Security Token Service)** = the AWS service that issues temporary credentials and
  answers "who is this caller?" via the `GetCallerIdentity` action.
- **Pre-signed URL** = a URL with a cryptographic signature baked in, so whoever receives
  it can call it *once* to verify the caller — without needing the caller's secret keys.
- **base64** = a way to encode binary/awkward text as safe plain characters. It is
  **encoding, not encryption** — anyone can decode it (which is exactly what we do here).
- **`$(...)`** = "command substitution": run the inner command and capture its output into
  a variable.

---

## 3. Line-by-line breakdown

### Line 1 — get the token
```bash
TOKEN_DATA=$(aws eks get-token --cluster-name eks-auto | jq -r '.status.token')
```
| Piece | Meaning |
|-------|---------|
| `aws eks get-token --cluster-name eks-auto` | Ask AWS to mint an auth token for the `eks-auto` cluster. Output is JSON. |
| `\| jq -r '.status.token'` | Pipe that JSON into `jq` and pull out just the `.status.token` field. `-r` = raw (no quotes). |
| `TOKEN_DATA=$(...)` | Store the resulting token string in a variable called `TOKEN_DATA`. |

### Line 2 — show the raw token
```bash
echo $TOKEN_DATA
```
Prints the whole token. It begins with `k8s-aws-v1.` followed by a long base64 blob.

### Line 3 — split the token on the dots
```bash
IFS='.' read header payload signature <<< "$TOKEN_DATA"
```
| Piece | Meaning |
|-------|---------|
| `IFS='.'` | Set the "Internal Field Separator" to a dot, so text is split on `.`. |
| `read header payload signature` | Read the split pieces into three variables. |
| `<<< "$TOKEN_DATA"` | Feed the token string in as input (a "here-string"). |

The token has the shape `k8s-aws-v1.<base64payload>...`, so `payload` ends up holding the
encoded middle part we want to decode.

### Line 4 — decode the payload
```bash
echo "$payload" | fold -w 4 | sed '$ d' | tr -d '\n' | base64 --decode
```
| Piece | Meaning |
|-------|---------|
| `echo "$payload"` | Print the encoded payload. |
| `fold -w 4` | Wrap the text into lines 4 characters wide. |
| `sed '$ d'` | Delete the **last** line (trims trailing padding so decoding is clean). |
| `tr -d '\n'` | Remove the newlines again, gluing it back into one string. |
| `base64 --decode` | Decode the base64 back into human-readable text. |

The `fold`/`sed`/`tr` dance is a trick to strip a stray trailing character before decoding.

---

## 4. Why we run it in the workshop

- To **see with your own eyes** how EKS turns your AWS identity into cluster access: the
  token is literally a signed STS `GetCallerIdentity` request.
- It demystifies the "magic" of `kubectl` auth on EKS and reinforces that **IAM is the
  source of truth** for who can reach the cluster.

---

## 5. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE, cluster `eks-auto`, region `us-west-2`)

**Raw token (truncated for safety):**
```
k8s-aws-v1.aHR0cHM6Ly9zdHMudXMtd2VzdC0yLmFtYXpvbmF3cy5jb20vP...
```
(The full token was 2367 characters long.)

**Decoded payload (secrets truncated):**
```
https://sts.us-west-2.amazonaws.com/?Action=GetCallerIdentity&Version=2011-06-15
  &X-Amz-Algorithm=AWS4-HMAC-SHA256
  &X-Amz-Credential=ASIA...%2F20260929%2Fus-west-2%2Fsts%2Faws4_request
  &X-Amz-Date=20260929T020208Z
  &X-Amz-Expires=60
  &X-Amz-SignedHeaders=host%3Bx-k8s-aws-id
  &X-Amz-Security-Token=IQoJb3Jp...   (long, redacted)
  &X-Amz-Signature=6674cffb...        (redacted)
```

**How to read it — this confirms the theory exactly:**
- `Action=GetCallerIdentity` → the URL asks STS "who is calling?"
- `X-Amz-Expires=60` → the pre-signed URL is only valid for **60 seconds** (short-lived,
  by design).
- `X-Amz-SignedHeaders=host;x-k8s-aws-id` → the cluster name is bound into the signature,
  so a token for one cluster can't be replayed against another.
- `X-Amz-Signature=...` → the cryptographic proof the webhook validates.

Exit status: `0` (success).

> **Security note:** an EKS auth token is a **live credential**. Anyone who captures it
> within its 60-second window could impersonate you to the cluster. That is why the real
> values above are **truncated/redacted** in this log and should never be committed to
> GitHub in full.

---

## 6. Handy related commands

```bash
aws sts get-caller-identity          # Directly show who you are (account, ARN, UserId)
aws eks get-token --cluster-name eks-auto   # See the full raw token JSON
kubectl config current-context       # Which cluster/context kubectl is pointed at
```
