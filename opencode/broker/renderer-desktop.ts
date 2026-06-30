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
 */

import { resolveVoiceEnabled } from './edge-tts-lib.ts';

const arg = (flag: string): string | null => {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] ?? null : null;
};
const BROKER = arg('--broker') || process.env.PULSE_BROKER_URL || 'http://localhost:31337';
const NAME = arg('--name') || 'desktop';
const FOCUS = arg('--focus');
const TTS = process.argv.includes('--tts');
const MUTE = process.argv.includes('--mute');
const TTS_PROVIDER = arg('--tts-provider') || process.env.PULSE_TTS_PROVIDER || 'edge_tts';

async function hasBin(bin: string): Promise<boolean> {
  const proc = Bun.spawn(['which', bin], { stdout: 'ignore', stderr: 'ignore' });
  return (await proc.exited) === 0;
}

const canNotify = await hasBin('notify-send');

type Speaker = {
  cmd: string[];
  mode: 'plain' | 'json';
  label: string;
};

function splitCommand(command: string): string[] {
  return command.split(/\s+/).map((part) => part.trim()).filter(Boolean);
}

// ─── Speech engine ─────────────────────────────────────────
// PULSE_TTS_CMD is an escape hatch for any long-running command that reads one
// plain-text utterance per stdin line. Without it, --tts uses the bundled Edge
// TTS speaker and sends JSON lines so language can select the voice.
function resolveSpeaker(): Speaker | null {
  if (process.env.PULSE_TTS_CMD) {
    return { cmd: splitCommand(process.env.PULSE_TTS_CMD), mode: 'plain', label: 'PULSE_TTS_CMD' };
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
          if (MUTE && myId) {
            await fetch(`${BROKER}/presence`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ id: myId, listening: false }),
            });
            console.log('[renderer] presence: muted');
          }
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
