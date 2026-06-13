# Install Smoke Workflow

This workflow verifies that the repo still installs correctly for a **fresh user** and does not accidentally depend on the principal's existing local runtime.

## Two Layers

### 1. Fast smoke: isolated HOME (default)

Use this on every meaningful installer/runtime change.

```bash
HOME=/tmp/opencode-smoke-user rm -rf /tmp/opencode-smoke-user
mkdir -p /tmp/opencode-smoke-user

HOME=/tmp/opencode-smoke-user bash opencode/install.sh
HOME=/tmp/opencode-smoke-user bash /tmp/opencode-smoke-user/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The installer will auto-bootstrap `opencode` and `bun` if they are missing from the environment, unless `--no-bootstrap` is passed.

**Expected result:**
- install succeeds
- structural validator passes
- behavioral suite passes
- E2E suite passes
- Pulse daemon/broker health is **not required**; installed scaffold and broker assets are validated, not a live service

This is the cheapest reproducibility test and should be the normal gate for installer work.

---

### 2. Full smoke: dedicated local test user (optional but ideal)

Use this before releases or major installer changes.

**Why:** it catches problems that `HOME=/tmp/...` can miss, such as real permissions, user-home initialization, and first-login assumptions.

Example flow (requires admin/sudo on the machine):

```bash
# Example only — adapt to your distro / local policy
sudo useradd -m -s /bin/bash opencode-smoke
sudo -u opencode-smoke -H bash -lc '
  cd /path/to/PAI-opencode && \
  bash opencode/install.sh && \
  bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
'
```

**Expected result:** same as the isolated HOME smoke, but now under a real separate user account.

---

## Current machine status

On this machine, the **isolated HOME** workflow is exercised and passing.

The **dedicated local test user** workflow was also exercised successfully. One operational nuance surfaced: for non-interactive shells, `opencode` and `bun` may need an explicit PATH if their installers appended only to shell init files. The repo installer itself now bootstraps both dependencies when missing.

## When to Run

- Always after changing:
  - `opencode/install.sh`
  - `opencode/bin/validate-pai-installation.sh`
  - `opencode/bin/test-behavioral.sh`
  - `opencode/bin/test-e2e-runtime.sh`
  - vendored `PAI/` bootstrap content
  - vendored `skills/`

- Strongly recommended before:
  - commits that change installation behavior
  - releases
  - large baseline syncs

## Failure interpretation

- **Install fails early** → missing repo baseline or broken installer assumptions
- **Structural fails** → self-contained content missing or wrong paths
- **Behavioral fails** → runtime/plugin regression
- **E2E fails** → cross-surface runtime regression or incomplete installed test assets

## Rule of thumb

If the repo does not pass the isolated HOME smoke test, it is not self-contained enough yet.
