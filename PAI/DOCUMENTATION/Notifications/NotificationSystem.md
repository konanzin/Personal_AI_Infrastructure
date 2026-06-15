# Notification System

The OpenCode port uses a file-first notification contract. The producer writes
human-relevant events to:

`~/.config/opencode/PAI/MEMORY/OBSERVABILITY/notifications.jsonl`

The optional Pulse Broker can tail that stream and fan events out to mobile or
desktop renderers. A live broker on `localhost:31337` is useful for renderers,
but it is not required for PAI to run and is not an installation success
criterion.

## Active Contract

- `pai_notify` is the only required final voice path.
- The visible `COMPLETED` line is not parsed for speech.
- `notifications.jsonl` is append-only contract v1.
- `pulse-broker.ts` is optional fan-out over SSE.
- Legacy `POST /notify` exists only when the optional broker is running.

## Completion Voice

Before a final response for completed work, the primary OpenCode agent calls the
native `pai_notify` tool exactly once:

```json
{
  "message": "Short speakable completion sentence.",
  "language": "pt-BR"
}
```

The same sentence should appear in the final visible completion line. The line
itself is for continuity and is not a trigger.

## Progress Notifications

Skills and workflows may emit legacy progress messages only as best-effort
compatibility:

```bash
(curl -s --max-time 2 -X POST http://localhost:31337/notify \
  -H "Content-Type: application/json" \
  -d '{"message": "Running the WORKFLOWNAME workflow in the SKILLNAME skill", "language": "en-US"}' \
  > /dev/null 2>&1 || true) &
```

Rules:

- Never block a task on this curl.
- Never treat a missing broker as failure.
- Include `language` for any payload intended to speak.
- Use `voice_enabled:false` for dashboard-only legacy progress.

## Out Of Scope

The original desktop Pulse daemon is not part of this OpenCode runtime:

- ElevenLabs VoiceServer.
- macOS MenuBar app.
- Next.js Observatory dashboard.
- Telegram/iMessage Pulse modules.
- Cron heartbeat daemon and AI reasoning jobs.

See also:

- `PAI/PULSE/README.md`
- `PAI/PULSE/PULSE.toml`
- `opencode/docs/NOTIFICATIONS_STREAM.md`
