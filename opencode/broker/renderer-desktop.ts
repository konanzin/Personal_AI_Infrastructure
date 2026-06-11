/**
 * Desktop renderer — minimal Pulse Broker consumer (Phase C2).
 *
 * Validation harness for the routing policy and the renderer protocol
 * before any Android work: prints every delivery, optionally raises a
 * desktop notification (notify-send) and speaks via system TTS.
 *
 * Run: bun renderer-desktop.ts [--broker http://localhost:31337]
 *        [--name desk] [--focus <sessionId>] [--tts] [--mute]
 */

const arg = (flag: string): string | null => {
  const i = process.argv.indexOf(flag);
  return i > -1 ? process.argv[i + 1] ?? null : null;
};
const BROKER = arg('--broker') || process.env.PULSE_BROKER_URL || 'http://localhost:31337';
const NAME = arg('--name') || 'desktop';
const FOCUS = arg('--focus');
const TTS = process.argv.includes('--tts');
const MUTE = process.argv.includes('--mute');

async function hasBin(bin: string): Promise<boolean> {
  const proc = Bun.spawn(['which', bin], { stdout: 'ignore', stderr: 'ignore' });
  return (await proc.exited) === 0;
}

const canNotify = await hasBin('notify-send');
const ttsBin = (await hasBin('spd-say')) ? 'spd-say' : (await hasBin('espeak-ng')) ? 'espeak-ng' : null;

function render(delivery: { event: any; render: { speak: boolean; reason: string }; dedupe_key: string }) {
  const { event, render: decision } = delivery;
  const icon = event.level === 'attention' ? '🚨' : event.level === 'digest' ? '📋' : '🔔';
  const speakMark = decision.speak ? '🔊' : `🔇(${decision.reason})`;
  console.log(`${icon} [${event.level}] ${event.speak || event.event} ${speakMark}`);

  if (canNotify && (decision.speak || event.level === 'attention')) {
    Bun.spawn(['notify-send', '-a', 'PAI', event.title || 'PAI', event.speak || event.event]);
  }
  if (TTS && ttsBin && decision.speak && event.speak) {
    Bun.spawn([ttsBin, event.speak]);
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
