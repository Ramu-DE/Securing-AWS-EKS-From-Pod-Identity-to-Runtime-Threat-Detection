# Command 02: Print key environment variables with `echo`

```bash
echo "AWS_REGION   = $AWS_REGION"
echo "ACCOUNT_ID   = $ACCOUNT_ID"
echo "EKS_CLUSTER  = $EKS_CLUSTER"
```

---

## Quick Summary (the 3 key points)

| # | Question | Answer |
|---|----------|--------|
| 1 | **Purpose of the command** | Print three environment variables to confirm the shell knows the region, account, and cluster before running dependent commands. |
| 2 | **What happens in Kubernetes** | **Nothing.** These are purely local shell commands; the cluster is never contacted. |
| 3 | **Which AWS service is called/used** | **None.** No AWS API call is made — the values were set earlier in the environment; `echo` just reads local variables. |

---

## 1. In one sentence

These three commands **print the values of three environment variables** so we can
confirm the workshop environment knows which AWS region, AWS account, and EKS cluster we
are working with.

---

## 2. Background concepts (for beginners)

- **Environment variable** = a named value that lives in your shell session (like a
  labeled box holding a piece of text). Programs and scripts read these boxes to learn
  settings without you retyping them every time. Example: `AWS_REGION` holds something
  like `us-west-2`.

- **`$` prefix** = "give me the *value* inside this box." Writing `AWS_REGION` is just the
  text "AWS_REGION"; writing `$AWS_REGION` means "the value stored in the variable named
  AWS_REGION."

- **`echo`** = a command that simply **prints text** to the terminal. Whatever you give
  `echo`, it displays back to you.

- **Double quotes `"..."`** = keep the text as one piece and still let the shell replace
  `$VARIABLE` with its value. (Single quotes `'...'` would print `$AWS_REGION` literally
  instead of its value — an important beginner gotcha.)

---

## 3. Breaking one line down piece by piece

Using the first line as the example:

```bash
echo "AWS_REGION   = $AWS_REGION"
```

| Piece | Meaning |
|-------|---------|
| `echo` | Print the following text to the screen. |
| `"..."` | Everything inside is one string; `$VARIABLE` inside will be expanded. |
| `AWS_REGION   = ` | Plain **label text** we typed (the extra spaces just line the output up neatly). |
| `$AWS_REGION` | Replaced by the **actual value** stored in the `AWS_REGION` variable. |

So if `AWS_REGION` holds `us-west-2`, the line prints: `AWS_REGION   = us-west-2`.

---

## 4. What each variable means

| Variable | What it holds | Why it matters |
|----------|---------------|----------------|
| `AWS_REGION` | The AWS region we're working in (e.g. `us-west-2`). | AWS resources live in a specific region; the CLI and cluster must target the right one. |
| `ACCOUNT_ID` | Your 12-digit AWS account number (e.g. `123456789012`). | Uniquely identifies your AWS account; used to build ARNs (resource identifiers) and ECR image paths. |
| `EKS_CLUSTER` | The name of the EKS cluster (e.g. `eks-auto`). | Tells commands which cluster to act on. |

---

## 5. How it works, step by step

1. You press Enter on the first line.
2. The shell sees `$AWS_REGION`, looks up that variable, and **substitutes its value**
   into the string. This happens *before* `echo` runs.
3. `echo` receives the finished text (label + value) and prints it.
4. The same happens for the second and third lines.

---

## 6. Why we run it in the workshop

- **Verify the environment is set up correctly** before running real commands. Many later
  commands rely on these variables (for example, building an ECR image URL from
  `ACCOUNT_ID` and `AWS_REGION`, or targeting the cluster named in `EKS_CLUSTER`).
- **Catch problems early.** If a value comes back **empty**, that variable was never set —
  and any later command depending on it would fail or behave unexpectedly.

---

## 7. Example output and how to read it

```
AWS_REGION   = us-west-2
ACCOUNT_ID   = 123456789012
EKS_CLUSTER  = eks-auto
```

Each line shows the label we typed on the left and the live value on the right.

**If a variable is empty**, you'll instead see nothing after the `=`:

```
AWS_REGION   = us-west-2
ACCOUNT_ID   =
EKS_CLUSTER  = eks-auto
```

Here `ACCOUNT_ID` is unset. You would need to set it, for example:

```bash
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

(`export` puts the value into a variable so other commands can read it too.)

---

## 8. Handy related commands

```bash
env | sort              # List ALL environment variables currently set
printenv AWS_REGION     # Print just one variable's value (alternative to echo)
echo $AWS_REGION        # Quick print without a label
```

---

## 9. Actual execution in this environment

**Run on:** 2026-09-29 (workshop IDE)

```bash
$ echo "AWS_REGION   = $AWS_REGION"
$ echo "ACCOUNT_ID   = $ACCOUNT_ID"
$ echo "EKS_CLUSTER  = $EKS_CLUSTER"
AWS_REGION   = us-west-2
ACCOUNT_ID   = <your 12-digit account id (masked)>
EKS_CLUSTER  = eks-auto
```

**Result:** exit status `0` (success). All three variables are set correctly:

| Variable | Value in this environment |
|----------|---------------------------|
| `AWS_REGION` | `us-west-2` |
| `ACCOUNT_ID` | `<12-digit account id — masked for publishing>` |
| `EKS_CLUSTER` | `eks-auto` |

None of the values came back empty, so the environment is configured properly and later
commands that depend on these variables (building ECR URLs, targeting the cluster, etc.)
will work as expected.
