# Hawking Shell CLI

**A lightweight, unofficial Bash client for submitting DCU School of Computing assignments to Hawking — without Python.**

This project is a shell-based alternative to DCU's [`hawkingCLI.py`](https://dcu-lecturing.pages.computing.dcu.ie/csc-1037-introduction-to-dev-ops/res/hawkingCLI.py). It uses the same Hawking API to authenticate, discover your available tasks, upload submissions, and display automated test results directly in your terminal.

> [!IMPORTANT]
> This is an **unofficial community adaptation**, not an official DCU tool. It submits files to the real Hawking service. Check the filename and module before uploading, and follow your lecturer's submission rules. Compatibility with the live service may change if DCU updates its API.

## Features

- **No Python required** — implemented in Bash using `curl` and `jq`.
- **Run from any directory** after a one-time installation as `hawking`.
- **Automatic task detection** — discovers the tasks associated with your account.
- **File or folder submission** — upload one file, multiple files, or the newest matching task file in a directory.
- **Module selection** — prompts when the same filename belongs to more than one module.
- **Test feedback** — prints individual test results, pass/fail totals, and the result-report URL.
- **macOS Keychain support** — securely stores your password via the built-in `security` command.
- **Meaningful exit codes** — returns a nonzero status for unsuccessful submissions or tests.

## Requirements

| Platform | Requirements | Password handling |
| --- | --- | --- |
| **macOS** (recommended) | Bash, `curl`, `jq` | macOS Keychain (`security`) |
| **Linux** | Bash, `curl`, `jq`, `stat` | Interactive password prompt on each run |

Bash and `curl` are generally preinstalled on macOS. **`jq` must be installed separately.** Native Windows Command Prompt / PowerShell execution is not supported; use a compatible Bash environment if needed, though Windows has not been tested.

### Install `jq`

**macOS (Homebrew):**

```bash
brew install jq
```

If Homebrew is not installed, see [brew.sh](https://brew.sh/).

**Ubuntu / Debian:**

```bash
sudo apt update
sudo apt install -y bash curl jq
```

## Installation (macOS)

### 1. Get the script

Clone or download this repository, then open Terminal **in the folder containing `hawking.sh`**.

### 2. Install the `hawking` command

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 hawking.sh "$HOME/.local/bin/hawking"
```

This makes the script executable and installs it under a short command name. It does **not** require `sudo`.

### 3. Add it to your PATH

For the default macOS shell (zsh), run:

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

> If you already have `$HOME/.local/bin` in your PATH, you can skip this step. Run `echo "$PATH"` to check.

### 4. Set your School of Computing username

Use your **School of Computing account name**, not necessarily your Mac login name or full university email address.

For the current terminal session:

```bash
export HAWKING_USERNAME="YOUR_SOC_USERNAME"
```

To load it automatically in future Terminal sessions:

```bash
printf '\nexport HAWKING_USERNAME="YOUR_SOC_USERNAME"\n' >> "$HOME/.zshrc"
source "$HOME/.zshrc"
```

Replace `YOUR_SOC_USERNAME` with your actual username. You can check the configured value with:

```bash
echo "$HAWKING_USERNAME"
```

The client also checks `EINSTEIN_USERNAME`, `DCU_USERNAME`, and `SOC_USERNAME` in that order if `HAWKING_USERNAME` is unset. If none is defined, it falls back to your operating-system username; **set `HAWKING_USERNAME` explicitly** to avoid submitting under the wrong account.

Shared accounts such as `socguest`, `socexam`, and `exam` are blocked.

### 5. Verify the installation

```bash
hawking --version
```

Expected for the included shell script:

```text
hawking 2026-08-13-shell.1
```

View command help with:

```bash
hawking --help
```

## Usage

### Submit one file

```bash
hawking wk1-find-all-files.sh
```

### Submit multiple files

```bash
hawking git-weeks-1-and-2.bundle git-branches.bundle
```

### Submit from another directory

```bash
hawking ~/Documents/DevOps/wk1-find-all-files.sh
```

### Automatically select a task file in the current directory

```bash
hawking
```

With no arguments, the client looks in the **current working directory** and uploads the **most recently modified regular file whose filename matches one of your available Hawking tasks**.

### Automatically select a task file in another directory

```bash
hawking ~/Documents/DevOps
```

Each specified directory contributes **at most one** file: its newest matching task file. It does not upload every file in the directory or search subdirectories recursively. To submit every required task, pass the files explicitly.

### Mix paths and directories

```bash
hawking ./week1 ./week2/task2.sh
```

### Check the installed version

```bash
hawking -v
# or
hawking --version
```

### Show help

```bash
hawking -h
# or
hawking --help
```

## How submissions work

1. The client authenticates with Hawking using your School of Computing account.
2. It fetches the tasks currently available to your account.
3. It checks each requested filename against those task names.
4. If a task exists in multiple modules, it asks you which module to use.
5. It uploads the file to the relevant module via the Hawking API.
6. It displays the runner's test results and the report URL returned by the service.

**Your file's basename must match the task name exactly.** For example, `wk1-find-all-files.sh` and `wk1-find-all-files-final.sh` are different names; only the name Hawking recognizes can be submitted.

The Bash client **uploads your file**; it does not execute assignment files locally. To test a shell assignment before submitting it, you can separately use:

```bash
chmod +x wk1-find-all-files.sh
./wk1-find-all-files.sh
```

Only run scripts you trust.

### Example output

Illustrative example — actual task names, test counts, modules, and report IDs vary:

```text
[2026-10-13 20:00:00] Authenticated as YOUR_SOC_USERNAME
[2026-10-13 20:00:00] Fetched 5 task(s) for your module(s).
[2026-10-13 20:00:00] Checking for task wk1-find-all-files.sh...
[2026-10-13 20:00:00] Uploading wk1-find-all-files.sh for CSC1037
[2026-10-13 20:00:01] *** test 1 passed
[2026-10-13 20:00:01] *** test 2 passed

[2026-10-13 20:00:01] *** passed: 2 of 2
[2026-10-13 20:00:01] *** overall: correct

[2026-10-13 20:00:01] *** report: http://hawking.local/hawking/CSC1037/result/12345
[2026-10-13 20:00:01] Running took 1 seconds
```

The report host shown by Hawking may only be reachable from the relevant DCU network or access environment.

## Passwords and security

The client authenticates to `https://hawking.computing.dcu.ie/api` over HTTPS using HTTP Basic authentication, as in the original Python client.

**On macOS:**

- On first use, the CLI asks you to save your School of Computing password in **macOS Keychain**.
- Later runs retrieve the saved entry for your username.
- The Keychain service name is `ie.dcu.computing.hawking.shell`.
- The password is passed to `curl` through standard input as configuration rather than in command-line arguments.

To remove this CLI's saved Keychain entry:

```bash
hawking --forget-password
```

The next submission prompts for the password again. Use this if your password changes or authentication starts failing.

**On Linux or when the `security` command is not available:** the CLI prompts for a password without echoing it and does not intentionally store it on disk. You may have to enter it each run. If macOS Keychain is present but rejects a save operation, the script reports an error instead of silently falling back.

> [!WARNING]
> Never commit passwords, API credentials, `.env` files, or Keychain exports to GitHub. The client does not use the original Python tool's `~/.hawking-passwd.txt` file; it keeps its own Keychain entry on macOS. Review shell scripts before executing them with your university credentials.

## Command reference

| Command | Description |
| --- | --- |
| `hawking` | Upload the newest matching task file in the current directory. |
| `hawking FILE` | Upload a specified file. |
| `hawking FILE1 FILE2` | Upload multiple specified files. |
| `hawking DIRECTORY` | Upload the newest matching task file in that directory. |
| `hawking --version` / `hawking -v` | Print the shell CLI version. |
| `hawking --help` / `hawking -h` | Print help. |
| `hawking --forget-password` | Delete the saved macOS Keychain password for the current username. |

### Environment variables

Username resolution priority:

1. `HAWKING_USERNAME`
2. `EINSTEIN_USERNAME`
3. `DCU_USERNAME`
4. `SOC_USERNAME`
5. Current OS username (fallback)

Set **only your username**, not your password, in shell startup files.

### Exit codes

| Code | Meaning |
| --- | --- |
| `0` | The command completed successfully, including passing all returned tests for submitted tasks. |
| `1` | General failure: authentication, network/API error, unrecognized task, missing file, or failed test(s). |
| `2` | A Hawking runner reported a submission error, or an unsupported CLI option was supplied. |

For multiple files, a nonzero exit code indicates that at least one file encountered a problem. Read the per-file output to identify it. Exit codes reflect the client and server responses; they do not override your lecturer's grading or submission deadlines.

## Troubleshooting

<details>
<summary><strong><code>hawking: command not found</code></strong></summary>

Check that the script was installed and that `~/.local/bin` is in your PATH:

```bash
ls -l "$HOME/.local/bin/hawking"
echo "$PATH"
source "$HOME/.zshrc"
```

If necessary, rerun the installation commands above.

</details>

<details>
<summary><strong><code>Missing dependency: jq</code></strong></summary>

Install it with `brew install jq` on macOS, then try again.

</details>

<details>
<summary><strong>Authentication fails</strong></summary>

Confirm your School of Computing username:

```bash
echo "$HAWKING_USERNAME"
```

On macOS, clear the saved password and retry:

```bash
hawking --forget-password
hawking --version  # Check the CLI; this does not authenticate.
hawking            # Prompts for credentials and tries a submission.
```

If you cannot authenticate with the same account through the university's normal systems, contact School of Computing support or your lecturer.

</details>

<details>
<summary><strong><code>You do not have a task named ...</code> or <code>No task files found to upload</code></strong></summary>

Verify the filename against the exact name on the labsheet. Ensure the task is available to your account. For automatic directory submission, check that the file is directly inside the directory (not a nested folder). You can always submit a specific path explicitly.

</details>

<details>
<summary><strong>HTTP errors, missing test results, or service problems</strong></summary>

Check your internet connection and whether the Hawking service is available. An API change can break an unofficial client. If an upload is time-sensitive, follow the official submission instructions and contact teaching staff if needed. Avoid repeatedly uploading when the server response is ambiguous.

</details>

## Development

The entry point is [`hawking.sh`](./hawking.sh). It is intended to run with Bash, not `sh`.

```bash
# Check Bash syntax
bash -n hawking.sh

# Run directly without installing
bash hawking.sh --version
```

Optional static analysis, if you have [ShellCheck](https://www.shellcheck.net/) installed:

```bash
shellcheck hawking.sh
```

The shell edition uses these Hawking API endpoints:

```text
GET  /api/auth
GET  /api/tasks
GET  /api/moduleForTask/{taskFilename}
POST /api/upload/{moduleId}/{taskFilename}
```

These are **observed from the provided Python client** and are not a promise of a stable public API. Real submissions depend on the upstream service.

## Upstream, attribution and licensing

This project is an **unofficial Bash adaptation** of the School of Computing's [Hawking Python CLI](https://dcu-lecturing.pages.computing.dcu.ie/csc-1037-introduction-to-dev-ops/res/hawkingCLI.py). Credit for the Hawking system and original Python client belongs to their respective authors.

The original contributions to this shell implementation are offered under the [MIT License](./LICENSE), copyright © 2026 CG-5228. **That license does not cover DCU's Hawking service or the upstream Python client, and it cannot override the rights of their respective copyright holders.**

The licensing terms for the original Python client could not be verified. Since this tool adapts its behaviour and API, check with the upstream maintainers whether permission is needed to publish or distribute the adaptation. An MIT license for new code by itself does not grant permission to redistribute protected upstream code.

This repository is **not affiliated with or endorsed by Dublin City University**.
