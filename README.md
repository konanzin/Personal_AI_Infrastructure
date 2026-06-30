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

The installer is idempotent. It preserves installed `USER` and `MEMORY` data, updates plugins/agents/commands/config/scripts, prepares the managed Edge TTS venv at `~/.config/opencode/tts-venv`, and removes the obsolete root-level `pai-hooks.lib.js` plugin copy.

## Included Surface

- One OpenCode plugin with native event handlers for PAI hook behavior
- 15 OpenCode agent files (BrowserAgent, QATester, and UIReviewer were retired — web verification and QA are handled by the Interceptor skill)
- PAI skills loaded from `~/.config/opencode/skills`, with legacy `~/.claude/` paths rewritten at install time
- PAI core directories for Algorithm, Memory, optional Pulse scaffolding, Tools, Templates, and User context
- Default PAI runtime injection on normal prompts (model decides mode)
- OpenCode slash commands for `/pai`, `/status`, `/interview`, `/pulse` (diagnostic scaffold only), `/voice`, `/context`, `/context-search` (alias `/cs`), `/pu`, and `/e1` through `/e5`
- **Notifications stream + Pulse Broker** (optional runtime): the plugin emits human-relevant events to `MEMORY/OBSERVABILITY/notifications.jsonl` (stable contract, `opencode/docs/NOTIFICATIONS_STREAM.md`); the broker on port 31337 fans them out to identified renderers — desktop (Edge TTS by default, `PULSE_TTS_CMD` override) and the mobile app (background voice). Roadmap and design: `PULSE_MOBILE_PLAN.md`, `mobile-app/docs/ADR-001-BACKGROUND-DELIVERY.md`

## Current Scope Boundary

The upstream desktop-heavy Pulse daemon remains out of scope. This branch now ships a lean **optional Pulse Broker** on port 31337 (`opencode/broker/`) that tails `notifications.jsonl`, exposes `/health` and `/notify`, and fans events out to desktop/mobile renderers. It is installed by `opencode/install.sh`, and the default desktop voice dependency is bootstrapped during normal install, but a running broker is still **not** part of install success criteria.

## Useful Docs

- `REPO_MODEL.md` — how this repo is organized (inherited / adapted / native)
- `SYNC.md` — selective upstream sync workflow
- `INSTALL.md` — install/update details
- `opencode/docs/README-OPENCODE.md` — architecture notes
- `opencode/docs/CHANGELOG-OPENCODE.md` — historical port changes
- `opencode/docs/TROUBLESHOOTING.md` — operational troubleshooting

## Design Rule

Prefer OpenCode-native behavior over Claude Code emulation shims. Keep compatibility where it preserves real PAI behavior, and keep `/pai` optional rather than required.
