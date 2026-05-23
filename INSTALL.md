# Install PAI for OpenCode

## Prerequisites

- `git`
- `curl`

`opencode` and `bun` are now **bootstrapped automatically** by the installer when missing. Use `--no-bootstrap` if you want strict failure instead.

## Update Existing Install

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

## Fresh Install From This Repo

```bash
cd ~/PAI-opencode
./opencode/install.sh
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Strict mode (do not auto-install dependencies):

```bash
./opencode/install.sh --no-bootstrap
```

## What The Installer Updates / Bootstraps

- `~/.config/opencode/plugins/pai-hooks.js`
- `~/.config/opencode/plugins/lib/pai-hooks.lib.js`
- `~/.config/opencode/plugins/lib/mode-classifier.lib.js`
- `~/.config/opencode/agents/*.md`
- `~/.config/opencode/commands/*.md`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/PAI/bin/*.sh`
- PAI metadata files from `opencode/config/`
- `opencode` binary when missing
- `bun` runtime when missing

## Pulse Scope

This installer ships the **Pulse scaffold** only:

- `~/.config/opencode/PAI/PULSE/PULSE.toml`
- related docs and directory structure

It does **not** currently provision or start a supported Pulse daemon/runtime. A missing `localhost:31337` service is therefore **not** treated as an installation failure for this branch.

It also removes the obsolete `~/.config/opencode/plugins/pai-hooks.lib.js` root copy because OpenCode auto-discovers root plugin files.

## Preserved Data

The installer does not intentionally delete installed `USER` or `MEMORY` data. Update mode creates a timestamped backup of `~/.config/opencode/PAI` before writing files.

## Validate

Expected successful state:

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The validator currently checks 75 structural points and then runs the behavioral and E2E suites. Its Pulse checks validate **Pulse scaffolding presence**, not a live daemon.
