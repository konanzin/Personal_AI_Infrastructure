# PAI for OpenCode

PAI v5 for OpenCode is a native OpenCode port of Personal AI Infrastructure. The goal is maximum practical parity with the Claude Code version while using OpenCode-native config, agents, skills, plugins, commands, and paths.

## Current Reality

- Runtime config: `~/.config/opencode/opencode.jsonc`
- PAI core: `~/.config/opencode/PAI/`
- Agents: `~/.config/opencode/agents/*.md`
- Skills: `~/.config/opencode/skills/*/SKILL.md`
- Plugin: `~/.config/opencode/plugins/pai-hooks.js`
- Plugin library: `~/.config/opencode/plugins/lib/pai-hooks.lib.js`
- Validation target: 66 checks from `opencode/bin/validate-pai-installation.sh`

PAI is installed as the default behavior for normal OpenCode prompts. `/pai` remains available as a manual shortcut/debug command, but should not be required for day-to-day use.

This port is not a perfect Claude Code clone. The strongest parity is in filesystem layout, agents, skills, tool/security tracking, startup context injection, and installation. Some lifecycle semantics still differ from Claude Code.

## Install Or Update

```bash
cd ~/PAI-opencode
./opencode/install.sh --update
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

The installer is idempotent. It preserves installed `USER` and `MEMORY` data, updates plugins/agents/commands/config/scripts, and removes the obsolete root-level `pai-hooks.lib.js` plugin copy.

## Included Surface

- One OpenCode plugin with native event handlers for PAI hook behavior
- 18 OpenCode agent files
- PAI skills loaded from `~/.config/opencode/skills`
- PAI core directories for Algorithm, Memory, Pulse, Tools, Templates, and User context
- Default PAI runtime injection on normal prompts (model decides mode)
- OpenCode slash commands for `/pai`, `/status`, `/interview`, `/pulse`, `/context`, `/rate`, and `/e1` through `/e5`

## Useful Docs

- `INSTALL.md` — install/update details
- `SYNC.md` — upstream sync workflow
- `opencode/docs/README-OPENCODE.md` — architecture notes
- `opencode/docs/CHANGELOG-OPENCODE.md` — current parity notes
- `opencode/docs/TROUBLESHOOTING.md` — operational troubleshooting

## Design Rule

Prefer OpenCode-native behavior over Claude Code emulation shims. Keep compatibility where it preserves real PAI behavior, and keep `/pai` optional rather than required.
