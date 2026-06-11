# Notifications Stream — Contract v1

`MEMORY/OBSERVABILITY/notifications.jsonl` is the **producer side** of the Pulse-mobile design (see `PULSE_MOBILE_PLAN.md`). The pai-hooks plugin appends one JSON object per line for events worth a human's attention. Renderers (mobile app, desktop notifier, future broker) consume it; the producer never routes, rate-limits, deduplicates across consumers, or calls an LLM.

This schema is a **stable contract**: additive changes only; breaking changes bump `v`.

## Envelope

```json
{
  "v": 1,
  "timestamp": "2026-06-11T18:00:00.000Z",
  "level": "milestone | attention | digest",
  "event": "<event type>",
  "session_id": "ses_...",
  "slug": "20260611-180000_my-task_ab12cd | null",
  "title": "human-friendly work title | null",
  "speak": "one speakable sentence (≤160 chars), template-generated",
  "data": { "event-specific fields": "..." }
}
```

- `speak` is always **deterministic** (built from event fields by `buildSpeak()` in `pai-hooks.lib.js`). Renderers MAY ignore it and build their own localized phrase from `event` + `data` — `speak` is the English default, localization is a renderer concern.
- Routine activity (individual tool calls, classifier decisions) never appears here — that is what `tool-activity.jsonl` and the other observability streams are for.

## Levels

| Level | Meaning | Renderer guidance |
|---|---|---|
| `milestone` | progress worth narrating | speak/notify; coalesce bursts (e.g. 10s window per session, keep the latest) |
| `attention` | the principal is needed now | always deliver; bypass coalescing windows |
| `digest` | end-of-work summary | notify when away; show on demand |

## Events

| `event` | Level | Emitted when | `data` fields |
|---|---|---|---|
| `session_started` | milestone | a session starts attached to tracked work (existing ISA slug found at `session.created`). Plain native sessions start silently. | `project` |
| `phase_transition` | milestone | ISA frontmatter `phase` changes (detected inside `syncISAToWorkRegistry` — the single source of truth for phase) | `phase`, `previous_phase`, `progress` |
| `agent_completed` | milestone | a `🎯 COMPLETED:` line appears in an assistant message (`message.updated`); deduped per message | `completed_line`, `agent`, `message_id` |
| `guard_denied` | attention | AgentGuard or SkillGuard hard-denies an invocation | `guard` (`agent`\|`skill`), `target`, `reason` |
| `security_blocked` | attention | SecurityPipeline blocks a bash command, sensitive write, or dangerous prompt | `tool` (`bash`\|`write`\|`edit`\|`prompt`), `reason`, `target?` |
| `tool_failing` | attention | the same tool fails 3 times in a row within a session (emitted once per streak; success resets it) | `tool`, `count`, `last_error` |
| `permission_needed` | attention | reserved (wired when the permission flow gains a notify point) | `tool?` |
| `session_completed` | digest | a session attached to tracked work is deleted (`session.deleted`) | `duration_human`, `final_phase`, `progress`, `status` |

## Consuming

```bash
tail -f ~/.config/opencode/PAI/MEMORY/OBSERVABILITY/notifications.jsonl | jq -r '"\(.level): \(.speak)"'
```

Consumer rules of thumb:

- Treat unknown `event` values as `milestone` unless `level` says otherwise (additive evolution).
- Dedupe on (`session_id`, `event`, `data.message_id`/`data.phase`) if you re-read the file from offset 0.
- The file is append-only with no rotation; consumers should track their own byte offset.

## Producer guarantees & limits

- Emission never throws into the main flow (failures are swallowed).
- In-memory dedupe/streak state resets on plugin reload — worst case is one duplicate or one missed `tool_failing`, never a corrupted stream.
- During streaming, `agent_completed` fires when the `🎯 COMPLETED:` line first appears (it terminates PAI responses, so the message is effectively complete).
