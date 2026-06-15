# Pulse Runtime Scope

This OpenCode port ships Pulse as an optional notification broker, not as the
original desktop Pulse daemon.

Implemented:

- `MEMORY/OBSERVABILITY/notifications.jsonl` as the append-only notification
  stream.
- `pai_notify` as the explicit final voice notification tool.
- `PAI/broker/pulse-broker.ts` as an optional SSE fan-out service.
- `PAI/broker/renderer-desktop.ts` as a reference/dev renderer.

Not implemented in this port:

- Next.js Observatory dashboard.
- macOS MenuBar app.
- ElevenLabs VoiceServer.
- Telegram/iMessage Pulse modules.
- Pulse cron daemon and scheduled reasoning jobs.

Install validation checks that the broker files and config are present. It does
not require `localhost:31337` to be running. Start the broker only when a mobile
or desktop renderer needs live fan-out.
