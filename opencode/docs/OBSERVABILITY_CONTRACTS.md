# Observability Contracts

PAI for OpenCode emits append-only JSONL streams for runtime observability. Producers are the OpenCode PAI plugin and shared plugin library; consumers may be tests, local scripts, the optional Pulse broker, or future mobile/backend renderers.

The producer contract is local-disk first. A live Pulse broker, dashboard, or HTTP server is never required for the streams to exist.

## Streams

| Stream | Installed path | Schema |
|--------|----------------|--------|
| Mode classifier | `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/mode-classifier.jsonl` | `~/.config/opencode/PAI/schemas/mode-classifier-event.schema.json` |
| Security events | `~/.config/opencode/PAI/MEMORY/STATE/security-events.jsonl` | `~/.config/opencode/PAI/schemas/security-event.schema.json` |
| Session events | `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/session-events.jsonl` | `~/.config/opencode/PAI/schemas/session-event.schema.json` |
| Tool failures | `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/tool-failures.jsonl` | `~/.config/opencode/PAI/schemas/tool-failure-event.schema.json` |
| Subagent trace | `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/subagent-trace.jsonl` | `~/.config/opencode/PAI/schemas/subagent-trace-event.schema.json` |
| Notifications | `~/.config/opencode/PAI/MEMORY/OBSERVABILITY/notifications.jsonl` | `~/.config/opencode/PAI/schemas/notification-event.schema.json` |
| Skill executions | `~/.config/opencode/PAI/MEMORY/SKILLS/execution.jsonl` | `~/.config/opencode/PAI/schemas/skill-execution-event.schema.json` |

Skill executions are runtime-owned since W2.6 (the model used to hand-echo these rows from skill prompts); rows without a `source` field are historical model-written entries — trust `source:"runtime"`.

`MEMORY/STATE/tool-activity.jsonl` is also emitted for local audit/debugging. It remains intentionally looser than the public contracts above because it captures broader tool metadata.

## Producer Guarantees

- Streams are append-only JSONL.
- Missing files mean empty streams on a fresh install.
- Event emission is best-effort and must not interrupt the primary user flow.
- Required schema fields are stable for v1; new optional fields may be added.
- Consumers should skip blank lines and tolerate a final partial line while tailing.

## Validation

Repository:

```bash
bun test opencode/tests/observability-schemas.test.ts
bun opencode/bin/validate-doc-integrity.js --repo
```

Installed runtime:

```bash
bun ~/.config/opencode/PAI/bin/validate-doc-integrity.js --root ~/.config/opencode
bash ~/.config/opencode/PAI/bin/validate-pai-installation.sh
```

## Consumer Guidance

Use `session_id` as the primary correlation key. Use `slug` when present for work-session identity. Unknown `event` values should be ignored or displayed generically unless the stream schema says otherwise.

### In-repo consumers

These streams are no longer write-only. The following ship as concrete consumers (see `HARNESS_QUALITY.md` for the quality rationale):

- `mode-classifier.jsonl` → `opencode/bin/monitor-classifier-health.js` — degradation monitor (ok/warn/alert on the share that fell off the LLM path).
- `LEARNING/SIGNALS/ratings.jsonl` → `opencode/bin/recall-feedback.js` (and the `/feedback` command) — on-demand, read-only recall of low-rating feedback.
- All six streams here → `opencode/tests/observability-schemas.test.ts` — a strict emitter-vs-schema round-trip: it drives the **real** emitters and validates the on-disk records, failing if an emitter renames or drops a field. Keep producer changes in sync with the schema in the same PR or this test goes red.
