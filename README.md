# PAI for OpenCode

This is a **self-contained agent product** built on PAI principles, not a live mirror of upstream. The repo holds everything needed to install and run PAI under OpenCode. `main` tracks the original PAI as a reference baseline; `opencode` (this branch) is the working product.

## Repo Model

Three kinds of content coexist here:

| Kind | What | Examples |
|------|------|----------|
| **Inherited** | Vendored baseline imported from the upstream PAI runtime. Treated as read-only reference; selective sync only. | `PAI/ALGORITHM/`, `PAI/DOCUMENTATION/`, `skills/*/SKILL.md` |
| **Adapted** | Upstream concepts reimplemented for OpenCode's native surfaces. | `opencode/plugins/pai-hooks.js`, `opencode/agents/*.md`, mode classifier, ISA sync, observability streams |
| **Native** | Original to this repo; no upstream equivalent. | `opencode/bin/validate-pai-installation.sh`, AgentGuard / SkillGuard, E2E runtime tests, deploy scripts |

Parity with upstream is an **initial baseline**, not a forever commitment. Future upstream sync is **selective and manual** — we pull what we want, when we want it, and adapt it to OpenCode's model. See `REPO_MODEL.md` for the full contract and `SYNC.md` for the practical workflow.

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
- PAI core directories for Algorithm, Memory, optional Pulse scaffolding, Tools, Templates, and User context
- Default PAI runtime injection on normal prompts (model decides mode)
- OpenCode slash commands for `/pai`, `/status`, `/interview`, `/pulse` (diagnostic scaffold only), `/context`, and `/e1` through `/e5`

## Current Scope Boundary

The current product includes **Pulse configuration scaffolding** (`PULSE.toml`, docs, and directory structure), but **does not ship a supported always-on Pulse daemon runtime**. Health endpoints like `localhost:31337` are therefore **not part of the install success criteria** for this branch right now.

## Useful Docs

- `REPO_MODEL.md` — how this repo is organized (inherited / adapted / native)
- `SYNC.md` — selective upstream sync workflow
- `INSTALL.md` — install/update details
- `opencode/docs/README-OPENCODE.md` — architecture notes
- `opencode/docs/CHANGELOG-OPENCODE.md` — current parity notes
- `opencode/docs/TROUBLESHOOTING.md` — operational troubleshooting

## Design Rule

Prefer OpenCode-native behavior over Claude Code emulation shims. Keep compatibility where it preserves real PAI behavior, and keep `/pai` optional rather than required.
