# Pulse-Mobile Plan — Notifications, Background Delivery, Broker & Voice

> **Status (2026-06-11):** Phase A SHIPPED (plugin v2.11.0, contract in `opencode/docs/NOTIFICATIONS_STREAM.md`). Phase C1 (broker) and C2 (desktop renderer) SHIPPED (`opencode/broker/`). Remaining: Phase B (background spike — needs the S24) and C3 (app integration, depends on B).

This is the implementation plan for rebuilding PAI's presence layer (originally: Pulse daemon + ElevenLabs voice on the desktop) as a multi-renderer system where the phone is the primary renderer. It covers the three phases agreed after the port-coherence pass.

Guiding theses (decided, not open):

1. **Notification is a runtime responsibility, not a prompt responsibility.** The plugin observes everything that matters (ISA phase changes, guards, session lifecycle, the `🎯 COMPLETED:` line); agents are not instructed to notify.
2. **The producer is dumb, the consumers are smart.** The plugin emits events without caring who listens. Routing (which device speaks) and coalescing (how often) live in the broker/renderers.
3. **Identity layers**: tokens are solved by per-message `agent` (done — `build-mobile`); notification routing is solved by identified subscriptions to *our* broker (OpenCode has no native client identity — verified against the API spec).

---

## Phase A — Notification event contract (`notifications.jsonl`)

**Goal:** a versioned, documented event stream the plugin emits and any renderer can consume. Testable with `tail -f`; no mobile work required.

### Event schema (v1)

One JSON object per line, appended to `MEMORY/OBSERVABILITY/notifications.jsonl`:

```json
{
  "v": 1,
  "timestamp": "ISO-8601",
  "level": "milestone | attention | digest",
  "event": "phase_transition | session_started | session_completed | agent_completed | guard_denied | security_blocked | tool_failing | permission_needed",
  "session_id": "...",
  "slug": "ISA slug or null",
  "title": "short display title",
  "speak": "one speakable sentence, 8-20 words, template-generated",
  "data": { "event-specific fields": "..." }
}
```

Rules:
- `speak` is **always template-generated** (deterministic, from event fields). No LLM in the emit path.
- Tool calls and routine activity NEVER produce events — that is what `tool-activity.jsonl` is for.
- The producer does no rate limiting or deduplication (thesis 2).

### Level taxonomy

| Level | Meaning | Sources |
|---|---|---|
| `milestone` | progress you'd want narrated | ISA phase transition; session start on a slug; `🎯 COMPLETED:` captured from a response |
| `attention` | needs the principal now | AgentGuard/SkillGuard deny; security block; same tool failing ≥3 times in a session; permission escalation |
| `digest` | end-of-work summary | session completed/archived: files touched, duration, phases walked, outcome line |

### Emit points (all already observed by the plugin)

| Emitter | Existing hook | Event |
|---|---|---|
| ISA sync detects `phase` change | `tool.execute.after` → `syncISAToWorkRegistry` | `phase_transition` (milestone) |
| Session registered on a slug | `session.created` | `session_started` (milestone) |
| `🎯 COMPLETED:` line in a response | `message.updated` (same scan as SatisfactionCapture) | `agent_completed` (milestone) — `speak` is the line itself |
| Guard deny / security block | `tool.execute.before` / `logSecurityEvent` | `guard_denied` / `security_blocked` (attention) |
| Repeated tool failures | `tool.execute.after` failure path | `tool_failing` (attention) |
| Session deleted with work metadata | `session.deleted` | `session_completed` (digest) |

### Work items

1. `plugins/lib/pai-hooks.lib.js`: `emitNotification(event)` helper (schema fill-in, appendJsonL, speak templates per event type) + export.
2. `plugins/pai-hooks.js`: call the helper from the six emit points above. Plugin version → 2.11.0.
3. Docs: `opencode/docs/NOTIFICATIONS_STREAM.md` — schema as a stable contract (same spirit as the observability table in README-OPENCODE).
4. Tests: bun unit tests per emit point (fixture state → assert one event with correct level/speak); behavioral checks (stream exists, helper wired); one new E2E scenario (simulated phase edit → event appears).
5. Validator counts re-baselined in docs.

**Exit criteria:** `tail -f ~/.config/opencode/PAI/MEMORY/OBSERVABILITY/notifications.jsonl` narrates a real session sensibly; suites green.

---

## Phase B — Background delivery spike (mobile)

**Goal:** decide how events reach the phone with the app backgrounded, on the tailnet, without FCM. This is the highest-uncertainty item — output is a decision, not production code.

### Options to prototype (in order)

1. **Foreground service + persistent connection** (`flutter_foreground_task` or platform channel): app keeps an SSE/WS subscription to the broker alive; renders local notifications + TTS. Test against Doze/App Standby (Samsung is aggressive — the S24 test device is the right worst case).
2. **ntfy self-hosted on the tailnet**: broker POSTs to ntfy topics; phone runs the ntfy app (or `ntfy` Flutter client) which already solved background delivery. Less code, one more moving part, voice/TTS integration is weaker (notification-only unless the app also subscribes).
3. **UnifiedPush** as a middle ground (self-hosted distributor, app receives push intents).

### Decision criteria

Battery impact over a workday; delivery reliability under Doze (test: phone idle 30+ min, event fires, measure latency); permission/UX cost (persistent notification tolerable?); implementation complexity in the existing Flutter app; whether TTS can fire from the background path.

### Work items

1. Throwaway spike branch; fake event generator (no Phase A dependency — a script appending to a JSONL + minimal SSE relay is enough).
2. Measure each option against the criteria on the Galaxy S24 (the adb/sshd test recipe from the mobile E2E environment applies).
3. Output: short ADR in `mobile-app/docs/` (decision + numbers), feeding Phase C's app integration.

**Exit criteria:** written decision with measured latency/battery numbers for at least options 1 and 2.

---

## Phase C — Minimal broker + renderers

**Goal:** the Pulse role, rebuilt lean: a small daemon that brokers events to identified renderers; desktop renderer first (validates routing cheaply), then the app.

### C1. Broker (Bun/TypeScript, consistent with PAI stack)

- **Ingest:** tail `notifications.jsonl` (fs.watch + offset tracking; no polling).
- **Subscriptions:** WS or SSE `/subscribe` with an identification handshake: `{ device: "desktop"|"phone", name, focusedSession?: string, listening: true }`. Renderers update presence (focus changes, foreground/background) over the same channel.
- **Routing policy v1 (simple, tolerant to error):**
  - Event for session S: if a subscriber declares `focusedSession == S`, suppress voice for everyone (you are watching it happen); badge-only.
  - Otherwise deliver to all subscribers; each event carries a `dedupe_key` so renderers in earshot of each other can be configured to defer (phone wins by default).
  - `attention` events always deliver everywhere.
- **Compat surface:** HTTP `/health` (the agents' voice gates start passing) and `/notify` accepting the upstream payload (`message`, `voice_id`, `title`, `phase`, `slug`) translated into a v1 event — inherited skills/tools that still curl the old endpoint work. Port 31337 to honor the install base.
- **No persistence beyond the JSONL** (the stream is the source of truth); no auth beyond tailnet reachability in v1.

### C2. Desktop renderer (validation harness)

- Minimal consumer: `notify-send` + system TTS (`espeak-ng`/`spd-say`), subscribes as `device: desktop`.
- Purpose: exercise the broker protocol and routing policy with two fake renderers before any Android work. Lives in `opencode/bin/` or a small `broker/` dir.

### C3. App integration (depends on Phase B decision)

- Subscribe via the Phase B mechanism; identify as `device: phone`, report foreground/background and the session being viewed.
- **Voice — `SpeechEngine` abstraction** (`speak(text, {voice})`), engine is a renderer detail, swappable in settings:
  - **Default: Android platform TTS** via `flutter_tts` (wrapper over `android.speech.tts.TextToSpeech`): free, offline, near-zero latency, background-safe, pt-BR voices.
  - **Optional: Gemini TTS** (cloud, Gemini 2.5 TTS family): premium quality, style control, multi-voice — enables per-agent voice mapping (parity with upstream's ElevenLabs voice_ids). Costs: API key, network, ~1-2s latency (fine for notifications), paid per use.
  - Not used: Gemini for *generating* speech text — `speak` stays template-deterministic at the producer (digest summaries are the only candidate for LLM-generated phrasing, ever).
- Speak `event.speak` verbatim.
- **Coalescing (renderer-side):** 10s window per session — multiple milestones collapse to the latest ("avançou de PLAN para VERIFY"); `attention` bypasses the window; digests only when backgrounded or on demand.
- **Settings:** mute toggle, per-level toggles (milestone/attention/digest), quiet hours.

### Work items / order

1. Broker ingest + `/subscribe` + `/health` + `/notify` compat (C1).
2. Desktop renderer + routing tests with two simulated subscribers (C2).
3. App subscription + TTS + coalescing + settings (C3, after Phase B ADR).
4. Install/run story: broker as a user systemd unit (template in `opencode/config/`), documented in INSTALL.md; explicitly still **not** an install success criterion.

**Exit criteria:** a real session driven from the desk stays silent at the desk and narrates milestones on the phone when you walk away; `/pu` reports broker health.

---

## Phase V0 — Foreground voice (DECLINED)

> **Decision (2026-06-11):** skipped by choice — voice ships only when the ecosystem is complete (contract → broker → background delivery), no stopgap adaptations. Section kept for the record.

## ~~Phase V0 — Foreground voice (optional early win, no new infra)~~

The app already holds an SSE connection to the OpenCode server and processes the message stream (that is how chat works). That makes a degraded-but-real voice experience possible **before** Phases B and C:

- On end-of-turn for the viewed session, extract the `🎯 COMPLETED:` line from the response text (the contract preserved exactly for this) and speak it via `flutter_tts`.
- Foreground-only, viewed-session-only, no routing — explicitly a stopgap, not the architecture.

**Why bother:** it validates the riskiest UX unknowns of voice (PT TTS quality, cadence, when speaking helps vs. irritates, phrase shape) for almost no cost, and everything learned feeds C3. The extraction logic and TTS/settings plumbing (mute toggle, language) carry over unchanged.

**Work items:** `🎯 COMPLETED:` parser on the existing stream handler; `flutter_tts` integration + speak-on-completion; a settings switch (off by default until tuned). Discard nothing later — C3 replaces only the event *source* (broker subscription instead of chat stream).

## Sequence & dependencies

```
Phase V0 (foreground voice) ── optional, anytime ──────────────────────────────► feeds C3 UX
Phase A (plugin contract)  ──────────► Phase C1/C2 (broker + desktop renderer) ──► C3 (app)
Phase B (background spike) ── parallel ────────────────────────────────────────► C3
```

Recommended start: Phase A — self-contained, all in already-mapped plugin territory, and every later phase consumes its output. Phase V0 can slot in whenever a quick morale/UX win is wanted.
