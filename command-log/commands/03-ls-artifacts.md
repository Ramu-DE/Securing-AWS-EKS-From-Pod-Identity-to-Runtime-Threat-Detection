# Command 03: `ls artifacts/`

```bash
ls artifacts/
```

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | List the contents of an `artifacts` folder (teaches relative vs absolute paths). |
| 2 | **What happens in Kubernetes** | **Nothing.** Local filesystem command only; the cluster is never contacted. |
| 3 | **Which AWS service is called/used** | **None.** Purely a local filesystem operation. |

---

## 1. In one sentence

This command tries to **list the contents of a folder named `artifacts`** — but *where*
it looks depends on which directory you are currently standing in.

---

## 2. Background concepts (for beginners)

- **`ls`** = "list" — shows the files and folders inside a directory.

- **Current working directory** = the folder your terminal is "standing in" right now.
  Every command runs relative to this location unless you say otherwise. Use `pwd`
  ("print working directory") to see where you are.

- **Relative path** (like `artifacts/`) = a path *relative to where you currently are*.
  `artifacts/` means "a folder called `artifacts` **inside my current folder**."

- **Absolute path** (like `/Workshop/artifacts/`) = a full path starting from the root
  `/`. It always points to the same place no matter where you're standing.

The trailing slash in `artifacts/` just makes it explicit that we expect a directory.

---

## 3. What happened in this environment (an instructive beginner error)

**Run on:** 2026-09-29 (workshop IDE)

```bash
$ pwd
/Workshop/artifacts/terraform

$ ls artifacts/
ls: cannot access 'artifacts/': No such file or directory   # EXIT: 2
```

**Why it failed:** we were standing in `/Workshop/artifacts/terraform`. The relative path
`artifacts/` told `ls` to look for
`/Workshop/artifacts/terraform/artifacts/` — a folder that does not exist. Hence
"No such file or directory" and a non-zero exit status of `2` (failure).

The `artifacts` folder actually lives one level **up** at `/Workshop/artifacts`.

---

## 4. The correct ways to run it

Any of these list the intended folder:

```bash
ls /Workshop/artifacts/        # absolute path — works from anywhere
ls ../                          # relative: ".." means "go up one level" (the parent)
cd /Workshop && ls artifacts/   # move to /Workshop first, THEN the relative path works
```

**Successful output** (`ls /Workshop/artifacts/`):

```
cfn
eks-security-workshop-central-stack.json
iam_policy.json
images
terraform
workshop-config.env
```

| Item | What it is |
|------|-----------|
| `cfn` | Folder of CloudFormation templates/artifacts. |
| `eks-security-workshop-central-stack.json` | A CloudFormation stack definition (JSON). |
| `iam_policy.json` | An IAM policy document. |
| `images` | Folder of images (likely diagrams/screenshots). |
| `terraform` | The Terraform folder we've been working in (contains `main.tf`, `devsecops/`, etc.). |
| `workshop-config.env` | Environment/config file for the workshop (likely where variables like `AWS_REGION` come from). |

---

## 5. Why this matters in the workshop

- It's a classic beginner pitfall: **the same command succeeds or fails depending on your
  current directory.** Always check `pwd` if a path "doesn't exist" when you expect it to.
- Understanding relative (`artifacts/`, `../`) vs absolute (`/Workshop/artifacts/`) paths
  prevents a huge share of "file not found" confusion.

---

## 6. Handy related commands

```bash
pwd            # Where am I right now?
ls             # List the current folder
ls -la         # Long listing incl. hidden files (names starting with ".") + permissions
ls ..          # List the parent folder
cd <path>      # Change into a different directory
```
