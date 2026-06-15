# OpenCode Observability System

PAI observability in the OpenCode port is an append-only JSONL contract produced by the OpenCode plugin and optionally consumed by the Pulse broker/renderers. It does not require the original desktop Pulse daemon, an HTTP dashboard, or Claude Code `.hook.ts` files.

## Runtime Producers

| Stream | Path | Producer | Purpose |
|--------|------|----------|---------|
| Tool activity | `MEMORY/STATE/tool-activity.jsonl` | `opencode/plugins/pai-hooks.js` `tool.execute.after` | Per-tool execution record |
| Mode classifier | `MEMORY/OBSERVABILITY/mode-classifier.jsonl` | `chat.message` classifier | Prompt mode/tier telemetry |
| Security events | `MEMORY/STATE/security-events.jsonl` | plugin security guards | Block/confirm/alert records |
| Session events | `MEMORY/OBSERVABILITY/session-events.jsonl` | session lifecycle handlers | Created, idle, archived, deleted, and state sync events |
| Tool failures | `MEMORY/OBSERVABILITY/tool-failures.jsonl` | `tool.execute.after` | Failed tool call diagnostics |
| Subagent trace | `MEMORY/OBSERVABILITY/subagent-trace.jsonl` | `tool.execute.after` | Skill and subagent invocation trace |
| Notifications | `MEMORY/OBSERVABILITY/notifications.jsonl` | `emitNotification()` / `pai_notify` | Contract v1 events for optional renderers |

All writes are best-effort append-only. Observability must never block the user request path.

## Schemas

The public contracts live under `opencode/schemas/`:

| Schema | Stream |
|--------|--------|
| `mode-classifier-event.schema.json` | `mode-classifier.jsonl` |
| `security-event.schema.json` | `security-events.jsonl` |
| `session-event.schema.json` | `session-events.jsonl` |
| `tool-failure-event.schema.json` | `tool-failures.jsonl` |
| `subagent-trace-event.schema.json` | `subagent-trace.jsonl` |
| `notification-event.schema.json` | `notifications.jsonl` |

Consumers should treat additional fields as forward-compatible and must key their parsing on the required fields in each schema.

## Consumer Rules

1. Read JSONL defensively: skip blank lines and malformed trailing partial lines.
2. Do not require Pulse to be running. The producer contract is local disk first.
3. Do not mutate observability streams. Consumers may maintain their own indexes or cursors.
4. Use `session_id` for correlation and `slug` where a stream provides work-session identity.
5. Treat missing streams as empty streams on a fresh install.

## Verification

The OpenCode test suite validates the emitted event shapes against the schemas. Install validation also checks that schemas and the doc-integrity CLI are present.

Use:

```bash
bun test opencode/tests/observability-schemas.test.ts
bun opencode/bin/validate-doc-integrity.js --repo
```

Installed runtime:

```bash
bun ~/.config/opencode/PAI/bin/validate-doc-integrity.js --root ~/.config/opencode
```
