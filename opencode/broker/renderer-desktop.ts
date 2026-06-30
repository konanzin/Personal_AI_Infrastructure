/**
 * Desktop renderer — minimal Pulse Broker consumer (Phase C2).
 *
 * Validation harness for the routing policy and the renderer protocol
 * before any Android work: prints every delivery, optionally raises a
 * desktop notification (notify-send) and optionally speaks through Edge TTS
 * or a caller-provided TTS command.
 *
 * Run: bun renderer-desktop.ts [--broker http://localhost:31337]
 *        [--name desk] [--focus <sessionId>] [--tts] [--mute]
 *        [--presence-mode loginctl|off] [--idle-poll <s>] [--idle-timeout <s>]
 */

import { readFileSync } from 'fs';
import { resolveVoiceEnabled } from './edge-tts-lib.ts';
import { dedupeKey, type NotificationEvent } from './broker-lib.ts';
import { createDedupeStore } from './renderer-dedupe.ts';

const arg = (flag: string): string | null => {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] ?? null : null;
};

// PULSE.toml's [renderers.desktop] block is the authoritative descriptor for
// this renderer. Read its string keys so the declared TTS defaults are real,
// not decorative. Falls back gracefully when the file is absent (dev runs).
function pulseRendererSetting(key: string): string | null {
  try {
    const path = new URL('../PULSE/PULSE.toml', import.meta.url).pathname;
    const toml = readFileSync(path, 'utf-8');
    const section = toml.split(/^\[/m).find((s) => s.startsWith('renderers.desktop]'));
    const match = section?.match(new RegExp(`^\\s*${key}\\s*=\\s*"([^"]*)"`, 'm'));
    return match ? match[1] : null;
  } catch {
    return null;
  }
}

const BROKER = arg('--broker') || process.env.PULSE_BROKER_URL || 'http://localhost:31337';
const NAME = arg('--name') || 'desktop';
const FOCUS = arg('--focus');
const TTS = process.argv.includes('--tts');
const MUTE = process.argv.includes('--mute');
const TTS_PROVIDER = arg('--tts-provider') || process.env.PULSE_TTS_PROVIDER || pulseRendererSetting('default_tts_provider') || 'edge_tts';
const TTS_OVERRIDE_ENV = pulseRendererSetting('tts_override_env') || 'PULSE_TTS_CMD';
const TTS_OVERRIDE_CMD = process.env[TTS_OVERRIDE_ENV];

// Presence: report `listening` to the broker based on whether the user is at
// this desktop, so voice plays where the human is and a locked/idle desktop
// stays quiet. `loginctl` (default) needs no extra dependency; `off` keeps the
// legacy behaviour (always listening). `--mute` is a hard override.
const PRESENCE_MODE = (arg('--presence-mode') || process.env.PULSE_PRESENCE_MODE || pulseRendererSetting('presence_mode') || 'loginctl').toLowerCase();
const IDLE_POLL_S = Math.max(3, Number(arg('--idle-poll') || process.env.PULSE_IDLE_POLL_S || pulseRendererSetting('idle_poll_s') || 15));
const IDLE_TIMEOUT_S = Number(arg('--idle-timeout') || process.env.PULSE_IDLE_TIMEOUT_S || pulseRendererSetting('idle_timeout_s') || 0);

async function hasBin(bin: string): Promise<boolean> {
  const proc = Bun.spawn(['which', bin], { stdout: 'ignore', stderr: 'ignore' });
  return (await proc.exited) === 0;
}

const canNotify = await hasBin('notify-send');

// Persistent dedupe: survives renderer/broker restarts so reconnects, /recent
// replay, and crashes never re-speak or re-notify an already-handled event.
const seen = createDedupeStore({
  path: process.env.PULSE_SEEN_PATH || undefined,
  capacity: Number(process.env.PULSE_SEEN_CAPACITY) || undefined,
});
// Flush on normal exit; on a signal, flush THEN exit — adding a signal listener
// suppresses Node/Bun's default termination, so we must exit explicitly or the
// renderer would ignore `systemctl stop`/SIGTERM.
process.on('beforeExit', () => seen.flush());
for (const sig of ['SIGTERM', 'SIGINT'] as const) {
  process.on(sig, () => {
    seen.flush();
    process.exit(0);
  });
}

type Speaker = {
  cmd: string[];
  mode: 'plain' | 'json';
  label: string;
};

function splitCommand(command: string): string[] {
  return command.split(/\s+/).map((part) => part.trim()).filter(Boolean);
}

// ─── Speech engine ─────────────────────────────────────────
// The override env (PULSE.toml tts_override_env, default PULSE_TTS_CMD) is an
// escape hatch for any long-running command that reads one plain-text utterance
// per stdin line. Without it, --tts uses the bundled Edge TTS speaker and sends
// JSON lines so language can select the voice.
function resolveSpeaker(): Speaker | null {
  if (TTS_OVERRIDE_CMD) {
    return { cmd: splitCommand(TTS_OVERRIDE_CMD), mode: 'plain', label: TTS_OVERRIDE_ENV };
  }
  if (/^(0|false|no|off|none)$/i.test(TTS_PROVIDER)) return null;
  if (TTS_PROVIDER === 'edge' || TTS_PROVIDER === 'edge_tts') {
    const script = new URL('./edge-tts-speaker.ts', import.meta.url).pathname;
    return { cmd: [process.execPath || 'bun', script], mode: 'json', label: 'edge_tts' };
  }
  return null;
}

let speaker: ReturnType<typeof Bun.spawn> | null = null;
let speakerMode: Speaker['mode'] = 'plain';
if (TTS) {
  const resolved = resolveSpeaker();
  if (resolved) {
    speakerMode = resolved.mode;
    speaker = Bun.spawn(resolved.cmd, { stdin: 'pipe', stdout: 'inherit', stderr: 'inherit' });
    console.log(`[renderer] speech engine: ${resolved.label} (${resolved.cmd.join(' ')})`);
  } else {
    console.log('[renderer] --tts requested but no speech engine configured');
  }
}

function speak(event: { speak?: string; language?: string }) {
  if (!speaker?.stdin) return;
  if (!resolveVoiceEnabled()) return;
  const text = (event.speak || '').replace(/\n+/g, ' ').trim();
  if (!text) return;
  try {
    const line = speakerMode === 'json'
      ? JSON.stringify({ text, language: event.language || 'en-US' })
      : text;
    speaker.stdin.write(`${line}\n`);
    speaker.stdin.flush();
  } catch {}
}

function render(delivery: { event: any; render: { speak: boolean; reason: string }; dedupe_key: string }) {
  const { event, render: decision } = delivery;

  // Idempotency: record before any side effect (notify/speak) and before the
  // voice-enabled check, so a previously-handled event is never repeated and a
  // later `/voice on` does not replay history. markAndCheckFresh returns false
  // for keys already seen in this run or loaded from the persistent ledger.
  const key = delivery.dedupe_key || dedupeKey(event as NotificationEvent);
  if (!seen.markAndCheckFresh(key)) return;

  const icon = event.level === 'attention' ? '🚨' : event.level === 'digest' ? '📋' : '🔔';
  const voiceEnabled = resolveVoiceEnabled();
  const speakMark = decision.speak ? (voiceEnabled ? '🔊' : '🔇(voice-off)') : `🔇(${decision.reason})`;
  console.log(`${icon} [${event.level}] ${event.speak || event.event} ${speakMark}`);

  if (canNotify && (decision.speak || event.level === 'attention')) {
    Bun.spawn(['notify-send', '-a', 'PAI', event.title || 'PAI', event.speak || event.event]);
  }
  if (decision.speak && event.speak) {
    speak(event);
  }
}

// ─── Presence (desktop is "away" when locked/idle/inactive) ──────────────────
async function runCapture(cmd: string[]): Promise<string> {
  try {
    const proc = Bun.spawn(cmd, { stdout: 'pipe', stderr: 'ignore' });
    const out = await new Response(proc.stdout).text();
    await proc.exited;
    return out;
  } catch {
    return '';
  }
}

function parseProps(text: string): Record<string, string> {
  const props: Record<string, string> = {};
  for (const line of text.split('\n')) {
    const eq = line.indexOf('=');
    if (eq > 0) props[line.slice(0, eq).trim()] = line.slice(eq + 1).trim();
  }
  return props;
}

let cachedSessionId: string | null | undefined;
async function resolveLoginSession(): Promise<string | null> {
  if (cachedSessionId !== undefined) return cachedSessionId;
  const envId = process.env.XDG_SESSION_ID;
  if (envId && (await runCapture(['loginctl', 'show-session', envId, '-p', 'Type'])).includes('Type=')) {
    return (cachedSessionId = envId);
  }
  const uid = process.getuid?.();
  let ids: string[] = [];
  if (uid != null) {
    ids = (parseProps(await runCapture(['loginctl', 'show-user', String(uid), '-p', 'Sessions'])).Sessions || '')
      .split(/\s+/)
      .filter(Boolean);
  }
  if (!ids.length) {
    ids = (await runCapture(['loginctl', 'list-sessions', '--no-legend']))
      .split('\n')
      .map((l) => l.trim().split(/\s+/)[0])
      .filter(Boolean);
  }
  let fallback: string | null = null;
  for (const id of ids) {
    const p = parseProps(await runCapture(['loginctl', 'show-session', id, '-p', 'Type', '-p', 'Active']));
    const type = (p.Type || '').toLowerCase();
    if (type === 'wayland' || type === 'x11') {
      if (p.Active === 'yes') return (cachedSessionId = id);
      fallback = fallback || id;
    }
  }
  return (cachedSessionId = fallback);
}

async function isAway(sessionId: string): Promise<boolean> {
  const p = parseProps(
    await runCapture(['loginctl', 'show-session', sessionId, '-p', 'LockedHint', '-p', 'Active', '-p', 'IdleHint', '-p', 'IdleSinceHint']),
  );
  if (p.LockedHint === 'yes') return true;
  if (p.Active === 'no') return true;
  if (p.IdleHint === 'yes') {
    if (IDLE_TIMEOUT_S > 0) {
      const sinceUs = Number(p.IdleSinceHint || 0);
      if (sinceUs > 0) return (Date.now() - sinceUs / 1000) / 1000 >= IDLE_TIMEOUT_S;
    }
    return true;
  }
  return false;
}

let lastListening: boolean | null = null;
async function reportPresence(id: string, listening: boolean): Promise<void> {
  if (lastListening === listening) return;
  lastListening = listening;
  try {
    await fetch(`${BROKER}/presence`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, listening }),
    });
    console.log(`[renderer] presence: ${listening ? 'listening' : 'away'}`);
  } catch {
    // Broker unreachable mid-flight; next tick (or reconnect) retries.
  }
}

async function startPresence(id: string): Promise<void> {
  if (MUTE) {
    await reportPresence(id, false); // hard override
    return;
  }
  if (PRESENCE_MODE === 'off') return; // legacy: broker default keeps us listening
  const sessionId = await resolveLoginSession();
  if (!sessionId) {
    console.log('[renderer] presence: no graphical session detected; staying listening (fail-open)');
    return;
  }
  const tick = async () => {
    try {
      await reportPresence(id, !(await isAway(sessionId)));
    } catch {
      // loginctl hiccup → leave last state, never fail closed.
    }
  };
  await tick();
  const interval = setInterval(tick, IDLE_POLL_S * 1000);
  if (typeof interval === 'object' && interval && 'unref' in interval) {
    (interval as { unref: () => void }).unref();
  }
}

// Seed the dedupe ledger from the broker ring buffer on every (re)connect.
// Recovered events are marked seen but NEVER spoken or notified (live-only
// rule), so reconnecting after time away does not replay a backlog aloud.
async function catchUp() {
  try {
    const res = await fetch(`${BROKER}/recent?n=200`);
    if (!res.ok) return;
    const body = (await res.json()) as { events?: NotificationEvent[] };
    let seeded = 0;
    for (const event of body.events ?? []) {
      if (seen.markAndCheckFresh(dedupeKey(event))) seeded += 1;
    }
    if (seeded) console.log(`[renderer] catch-up: seeded ${seeded} prior event(s) silently`);
  } catch {
    // Broker without /recent or transient error → nothing to seed.
  }
}

async function main() {
  const params = new URLSearchParams({ device: 'desktop', name: NAME });
  if (FOCUS) params.set('focus', FOCUS);

  console.log(`[renderer] connecting to ${BROKER}/subscribe (${NAME}${FOCUS ? `, focus=${FOCUS}` : ''}${MUTE ? ', muted' : ''})`);
  const res = await fetch(`${BROKER}/subscribe?${params}`);
  if (!res.ok || !res.body) {
    console.error(`[renderer] subscribe failed: ${res.status}`);
    process.exit(1);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let myId: string | null = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });

    let sep: number;
    while ((sep = buffer.indexOf('\n\n')) !== -1) {
      const frame = buffer.slice(0, sep);
      buffer = buffer.slice(sep + 2);
      const dataLine = frame.split('\n').find((l) => l.startsWith('data: '));
      if (!dataLine) continue; // heartbeat comment
      try {
        const payload = JSON.parse(dataLine.slice(6));
        if (payload.type === 'hello') {
          myId = payload.id;
          console.log(`[renderer] subscribed as ${myId} (policy ${payload.policy})`);
          await catchUp();
          if (myId) await startPresence(myId);
        } else if (payload.type === 'notification') {
          render(payload);
        }
      } catch {
        // skip malformed frame
      }
    }
  }
  console.log('[renderer] stream closed');
}

main();
