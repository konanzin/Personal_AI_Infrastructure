# Install PAI for OpenCode

## Prerequisites

- `git`
- `opencode`
- `bun` recommended

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

## What The Installer Updates

- `~/.config/opencode/plugins/pai-hooks.js`
- `~/.config/opencode/plugins/lib/pai-hooks.lib.js`
- `~/.config/opencode/agents/*.md`
- `~/.config/opencode/commands/*.md`
- `~/.config/opencode/opencode.jsonc`
- `~/.config/opencode/PAI/bin/*.sh`
- PAI metadata files from `opencode/config/`

It also removes the obsolete `~/.config/opencode/plugins/pai-hooks.lib.js` root copy because OpenCode auto-discovers root plugin files.

## Preserved Data

The installer does not intentionally delete installed `USER` or `MEMORY` data. Update mode creates a timestamped backup of `~/.config/opencode/PAI` before writing files.

## Validate

Expected successful state:

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The validator currently checks 66 installation and parity-critical structure points.
