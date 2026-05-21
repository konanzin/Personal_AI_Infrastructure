# PAI OpenCode Port Changelog

## Current Port State

This repository ports PAI from Claude Code to OpenCode-native configuration and plugin surfaces.

### Verified Architecture

| Area | Current State |
|------|---------------|
| Config | `~/.config/opencode/opencode.jsonc` generated from `opencode/config/opencode.jsonc.template` |
| Plugin | `pai-hooks.js` loaded explicitly through OpenCode `plugin` config |
| Plugin lib | `plugins/lib/pai-hooks.lib.js`, not root auto-loaded |
| Agents | 18 `.md` files installed under `~/.config/opencode/agents/` |
| Commands | `/pai`, `/status`, `/interview`, `/pulse`, `/context`, `/rate`, `/e1`-`/e5` |
| Memory | `~/.config/opencode/PAI/MEMORY/{STATE,WORK,KNOWLEDGE,LEARNING,RESEARCH}` |
| Validation | 66 checks in `validate-pai-installation.sh` |

### Parity Notes

| Claude Code Feature | OpenCode Port Status |
|---------------------|----------------------|
| SecurityPipeline | Native `tool.execute.before` implementation |
| ToolActivityTracker | Native `tool.execute.after` logging |
| ContentScanner | Native `tool.execute.after` scanning |
| Session cleanup | Adapted to OpenCode session lifecycle |
| Satisfaction capture | Captured from user messages where available |
| Work learning | Captured during session deletion where metadata exists |
| LoadContext | Partial: initializes state, but cannot fully inject dynamic system context |
| Default PAI behavior | OpenCode default build agent plus system transform with model-native mode classification; `/pai` not required |
| PromptGuard | Adapted: `chat.message` pre-sanitizes denied prompts before model context; `message.updated` still logs post-event findings |
| Voice | External Pulse notification only; no OpenCode-native voice |
| Statusline | Slash-command/status output instead of Claude Code sidebar |

### Removed Historical Noise

- Deleted the old bugfix review document because it described a point-in-time audit, not source of truth.
- Deleted the old incident report from the repo because active safety is now represented by installer behavior, validator checks, and plugin placement.
- Removed accidentally generated literal `${HOME}` test artifacts from the repository tree.

## Compatibility Principle

Do not describe the port as fully 1:1. Track concrete parity by behavior and validator coverage. `/pai` must remain optional, not required, for normal PAI operation.
