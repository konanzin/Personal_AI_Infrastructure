/**
 * Pulse Broker — pure logic (no I/O).
 *
 * The broker is the consumer-side router of the notifications contract
 * (opencode/docs/NOTIFICATIONS_STREAM.md). The producer (pai-hooks plugin)
 * stays dumb; everything about WHO should render an event and HOW lives here.
 *
 * Kept I/O-free so routing policy is unit-testable in isolation.
 */

export interface NotificationEvent {
  v: number;
  timestamp: string;
  level: 'milestone' | 'attention' | 'digest' | string;
  event: string;
  session_id: string;
  slug: string | null;
  title: string | null;
  speak: string;
  language: string;
  data: Record<string, unknown>;
}

export interface Subscriber {
  id: string;
  device: 'phone' | 'desktop' | string;
  name: string;
  /** Session the renderer is currently displaying, if any. */
  focusedSession: string | null;
  /** False = renderer asked to be silent (mute), still receives events. */
  listening: boolean;
}

export interface RenderDecision {
  speak: boolean;
  reason: string;
}

/**
 * Incrementally parse a JSONL chunk. Returns complete events and the
 * trailing partial line (to be prepended to the next chunk).
 */
export function parseJsonlChunk(chunk: string): { events: NotificationEvent[]; rest: string } {
  const lines = chunk.split('\n');
  const rest = lines.pop() ?? '';
  const events: NotificationEvent[] = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const parsed = JSON.parse(trimmed);
      if (parsed && typeof parsed === 'object' && typeof parsed.event === 'string') {
        events.push(parsed as NotificationEvent);
      }
    } catch {
      // Corrupt line: skip — the stream is append-only, a torn write only
      // affects the final line, which lands in `rest` instead.
    }
  }
  return { events, rest };
}

/**
 * Routing policy v1 (deliberately simple and error-tolerant):
 *
 * 1. `attention` always speaks, everywhere — the principal is needed.
 * 2. If ANY listening subscriber is displaying the event's session, voice is
 *    suppressed for everyone (you are watching it happen); renderers may
 *    still badge.
 * 3. A muted subscriber (`listening: false`) never speaks.
 * 4. Otherwise speak.
 *
 * Events are still DELIVERED to every subscriber regardless of the decision;
 * `speak` is a rendering hint, not a delivery filter.
 */
export function decideRender(
  event: NotificationEvent,
  allSubscribers: Subscriber[],
  target: Subscriber,
): RenderDecision {
  if (event.level === 'attention') {
    return { speak: target.listening, reason: target.listening ? 'attention-always' : 'muted' };
  }

  if (!target.listening) {
    return { speak: false, reason: 'muted' };
  }

  const watched = allSubscribers.some(
    (s) =>
      s.listening &&
      s.focusedSession !== null &&
      (s.focusedSession === event.session_id || (event.slug !== null && s.focusedSession === event.slug)),
  );
  if (watched) {
    return { speak: false, reason: 'session-on-screen' };
  }

  return { speak: true, reason: 'default' };
}

/**
 * Stable key so renderers in earshot of each other can defer/dedupe
 * (phone-wins is renderer configuration, not broker policy).
 */
export function dedupeKey(event: NotificationEvent): string {
  const marker =
    (event.data?.message_id as string | undefined) ??
    (event.data?.phase as string | undefined) ??
    event.timestamp;
  return `${event.session_id}:${event.event}:${marker}`;
}

/** Upstream Pulse /notify payload (NotificationSystem.md). */
export interface LegacyNotifyBody {
  message?: string;
  title?: string;
  voice_id?: string;
  voice_enabled?: boolean;
  phase?: string;
  slug?: string;
  agent?: string;
  level?: string;
  language?: string;
}

function normalizeNotificationLanguage(language: unknown): string | null {
  if (typeof language !== 'string') return null;
  const raw = language.trim().replace(/_/g, '-');
  if (!raw) return null;
  const [code, region] = raw.split('-');
  const lowerCode = code.toLowerCase();
  if (lowerCode === 'pt') return `pt-${(region ?? 'BR').toUpperCase()}`;
  if (lowerCode === 'en') return `en-${(region ?? 'US').toUpperCase()}`;
  return null;
}

/**
 * Translate an upstream-format POST /notify into a contract-v1 event.
 * Inherited skills/agents that still curl the old endpoint keep working;
 * their notifications join the same stream as the plugin's.
 */
export function translateLegacyNotify(body: LegacyNotifyBody, now: () => string = () => new Date().toISOString()): NotificationEvent | null {
  const message = typeof body?.message === 'string' ? body.message.trim() : '';
  if (!message) return null;

  const phase = typeof body.phase === 'string' && body.phase ? body.phase.toLowerCase() : null;
  const level = body.level === 'attention' || body.level === 'digest' ? body.level : 'milestone';
  // voice_enabled:false upstream meant "dashboard only" — map to a muted speak
  const speak = body.voice_enabled === false ? '' : message.replace(/\s+/g, ' ').slice(0, 160);
  const language = normalizeNotificationLanguage(body.language);
  if (speak && !language) return null;

  return {
    v: 1,
    timestamp: now(),
    level,
    event: phase ? 'phase_transition' : 'legacy_notify',
    session_id: 'legacy',
    slug: body.slug ?? null,
    title: body.title ?? body.agent ?? null,
    speak,
    language: language ?? 'en-US',
    data: {
      source: 'legacy_notify',
      ...(phase ? { phase } : {}),
      ...(body.agent ? { agent: body.agent } : {}),
      ...(body.voice_id ? { voice_id: body.voice_id } : {}),
    },
  };
}

/** Fixed-size in-memory history for late subscribers (GET /recent). */
export class RingBuffer<T> {
  private buf: T[] = [];
  constructor(private readonly capacity: number) {}
  push(item: T): void {
    this.buf.push(item);
    if (this.buf.length > this.capacity) this.buf.shift();
  }
  last(n: number): T[] {
    return this.buf.slice(-Math.max(0, n));
  }
  get size(): number {
    return this.buf.length;
  }
}
