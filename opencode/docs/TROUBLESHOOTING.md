# PAI for OpenCode Troubleshooting

## First Check

```bash
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The current validator checks 81 installation and parity-critical structure points, then runs the behavioral and E2E suites when they are installed.

## PAI Only Works With /pai

This is a parity bug. Normal prompts should load PAI behavior by default.

Check:

```bash
grep -n 'Default PAI primary agent' ~/.config/opencode/opencode.jsonc
grep -n 'experimental.chat.system.transform' ~/.config/opencode/plugins/pai-hooks.js
```

Fix:

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
```

Restart OpenCode after reinstalling.

## Model Does Not Enter Algorithm Mode

If the model stays in NATIVE for complex work, the system context may not be injecting correctly.

Check:

```bash
grep -n 'Mode Classification Rules' ~/.config/opencode/plugins/pai-hooks.js
```

The plugin injects classification rules into system context. The model decides the mode. If it under-classifies, that is a model behavior issue, not a plugin bug.

Fix: use `/e3` or higher explicitly in your prompt to force ALGORITHM mode.

## Plugin Lib Auto-Loaded From Root

Symptom: validation reports `pai-hooks.lib.js in plugins/ root`.

Fix:

```bash
mkdir -p ~/.config/opencode/plugins/lib
rm -f ~/.config/opencode/plugins/pai-hooks.lib.js
cd ~/PAI-opencode
./opencode/install.sh --update
```

OpenCode auto-discovers root plugin files. The library must stay in `plugins/lib/` so only `pai-hooks.js` is loaded as a plugin.

## Plugin Not Found

Check:

```bash
ls -la ~/.config/opencode/plugins/pai-hooks.js
grep -n 'pai-hooks.js' ~/.config/opencode/opencode.jsonc
```

Fix:

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
```

## Config Was Overwritten Or Is Invalid

The source of truth is `opencode/config/opencode.jsonc.template`.

Fix:

```bash
cd ~/PAI-opencode
cp opencode/config/opencode.jsonc.template ~/.config/opencode/opencode.jsonc
opencode --version
```

After changing OpenCode config/plugins/agents/skills, restart OpenCode because config is loaded at startup.

## Agents Missing

Check:

```bash
ls ~/.config/opencode/agents/*.md | wc -l
```

Fix:

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
```

## Skills Missing

Check:

```bash
ls ~/.config/opencode/skills
```

The installer copies skills only if this repo contains `skills/` or `opencode/skills/`. External/global skills may also be loaded by OpenCode depending on your config.

## Commands Missing

Commands are registered in `opencode.jsonc` and command markdown files are copied into `~/.config/opencode/commands/`.

Check:

```bash
grep -n '"pai"\|"status"\|"interview"' ~/.config/opencode/opencode.jsonc
ls ~/.config/opencode/commands
```

Fix:

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
```

## PAI Core Missing

Check:

```bash
ls ~/.config/opencode/PAI
```

This repo's installer preserves an existing PAI core and updates OpenCode-specific files. If `~/.config/opencode/PAI` was deleted, restore from backup or reinstall from the upstream PAI source that contains the full `PAI/` tree.

## Path Confusion

Canonical OpenCode path:

```text
~/.config/opencode/PAI
```

Do not rely on `~/.claude` for new OpenCode-native behavior. Legacy references may exist in old content, but new config and plugins should use `~/.config/opencode` or `${PAI_DIR}`.

## Clean Update

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

Restart OpenCode after the update.
