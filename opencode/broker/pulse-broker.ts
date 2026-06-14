/**
 * Pulse Broker — minimal event broker for the PAI notifications stream.
 *
 * Phase C1 of PULSE_MOBILE_PLAN.md. Tails MEMORY/OBSERVABILITY/
 * notifications.jsonl (the producer contract) and fans events out to
 * identified subscribers (mobile app, desktop renderer) over SSE, each
 * delivery carrying a per-subscriber render decision.
 *
 * Surfaces (port 31337 to honor the upstream Pulse install base):
 *   GET  /subscribe?device=&name=&focus=   SSE stream (hello event carries id)
 *   POST /presence  {id, focusedSession?, listening?}
 *   POST /notify    upstream Pulse payload -> appended to the stream
 *   GET  /health, /api/pulse/health        health (agents' voice gates probe these)
 *   GET  /recent?n=20                      ring-buffer catch-up
 *
 * No persistence beyond the JSONL: the stream is the source of truth.
 * Run: bun pulse-broker.ts [--port 31337] [--replay]
 */

import { existsSync, mkdirSync, openSync, readSync, fstatSync, closeSync, watch, appendFileSync } from 'fs';
import { join, dirname } from 'path';
import { homedir } from 'os';
import {
  parseJsonlChunk,
  decideRender,
  dedupeKey,
  translateLegacyNotify,
  RingBuffer,
  type NotificationEvent,
  type Subscriber,
} from './broker-lib.ts';

const BROKER_VERSION = '0.1.0';

// ─── Config ────────────────────────────────────────────────
const PAI_DIR = process.env.PAI_DIR || join(homedir(), '.config', 'opencode', 'PAI');
const STREAM_PATH = join(PAI_DIR, 'MEMORY', 'OBSERVABILITY', 'notifications.jsonl');
const argPort = process.argv.indexOf('--port');
const PORT = argPort > -1 ? Number(process.argv[argPort + 1]) : Number(process.env.PULSE_BROKER_PORT || 31337);
const REPLAY = process.argv.includes('--replay');

// ─── State ─────────────────────────────────────────────────
interface LiveSubscriber extends Subscriber {
  send: (payload: string) => void;
  close: () => void;
}

const subscribers = new Map<string, LiveSubscriber>();
const recent = new RingBuffer<NotificationEvent>(200);
let nextSubId = 1;

// ─── Tailer ────────────────────────────────────────────────
// fs.watch on the directory is the primary signal; a 1s safety interval
// covers watcher gaps (editors, network mounts). Both paths delta-read
// from `offset`, so double-firing is harmless.
let offset = 0;
let partial = '';

function readDelta(): void {
  if (!existsSync(STREAM_PATH)) return;
  let fd: number | null = null;
  try {
    fd = openSync(STREAM_PATH, 'r');
    const size = fstatSync(fd).size;
    if (size < offset) {
      // Truncated/rotated: start over
      offset = 0;
      partial = '';
    }
    if (size === offset) return;
    const len = size - offset;
    const buf = Buffer.alloc(len);
    readSync(fd, buf, 0, len, offset);
    offset = size;
    const { events, rest } = parseJsonlChunk(partial + buf.toString('utf-8'));
    partial = rest;
    for (const event of events) broadcast(event);
  } catch (e) {
    console.error(`[broker] tail error: ${(e as Error).message}`);
  } finally {
    if (fd !== null) closeSync(fd);
  }
}

function startTailer(): void {
  mkdirSync(dirname(STREAM_PATH), { recursive: true });
  if (!REPLAY && existsSync(STREAM_PATH)) {
    const fd = openSync(STREAM_PATH, 'r');
    offset = fstatSync(fd).size; // start at end: live events only
    closeSync(fd);
  }
  try {
    watch(dirname(STREAM_PATH), { persistent: true }, () => readDelta());
  } catch (e) {
    console.error(`[broker] fs.watch unavailable (${(e as Error).message}); relying on safety interval`);
  }
  setInterval(readDelta, 1000);
  readDelta();
}

// ─── Fan-out ───────────────────────────────────────────────
function broadcast(event: NotificationEvent): void {
  recent.push(event);
  const all = [...subscribers.values()];
  for (const sub of all) {
    const render = decideRender(event, all, sub);
    const frame = `data: ${JSON.stringify({ type: 'notification', event, render, dedupe_key: dedupeKey(event) })}\n\n`;
    try {
      sub.send(frame);
    } catch {
      drop(sub.id);
    }
  }
  console.log(`[broker] ${event.level} ${event.event} -> ${all.length} subscriber(s)`);
}

function drop(id: string): void {
  const sub = subscribers.get(id);
  if (!sub) return;
  subscribers.delete(id);
  try { sub.close(); } catch {}
  console.log(`[broker] subscriber ${id} (${sub.device}/${sub.name}) disconnected`);
}

// ─── HTTP ──────────────────────────────────────────────────
function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

const server = Bun.serve({
  port: PORT,
  idleTimeout: 0,
  async fetch(req) {
    const url = new URL(req.url);

    if (req.method === 'GET' && (url.pathname === '/health' || url.pathname === '/api/pulse/health')) {
      return json({
        status: 'ok',
        service: 'pulse-broker',
        version: BROKER_VERSION,
        subscribers: subscribers.size,
        stream: STREAM_PATH,
        offset,
      });
    }

    if (req.method === 'GET' && url.pathname === '/recent') {
      const n = Math.min(Number(url.searchParams.get('n') || 20), 200);
      return json({ events: recent.last(n) });
    }

    if (req.method === 'GET' && url.pathname === '/subscribe') {
      const id = `sub-${nextSubId++}`;
      const device = url.searchParams.get('device') || 'unknown';
      const name = url.searchParams.get('name') || device;
      const focus = url.searchParams.get('focus');

      let controllerRef: ReadableStreamDefaultController<Uint8Array>;
      const encoder = new TextEncoder();
      const stream = new ReadableStream<Uint8Array>({
        start(controller) {
          controllerRef = controller;
          const sub: LiveSubscriber = {
            id,
            device,
            name,
            focusedSession: focus || null,
            listening: true,
            send: (payload) => controller.enqueue(encoder.encode(payload)),
            close: () => { try { controller.close(); } catch {} },
          };
          subscribers.set(id, sub);
          sub.send(`data: ${JSON.stringify({ type: 'hello', id, policy: 'v1', heartbeat_s: 25 })}\n\n`);
          console.log(`[broker] subscriber ${id} (${device}/${name}) connected${focus ? `, focused on ${focus}` : ''}`);
        },
        cancel() {
          drop(id);
        },
      });

      // Heartbeat keeps proxies/tailnets from idling the connection out
      const heartbeat = setInterval(() => {
        const sub = subscribers.get(id);
        if (!sub) { clearInterval(heartbeat); return; }
        try { sub.send(`: hb\n\n`); } catch { clearInterval(heartbeat); drop(id); }
      }, 25_000);

      return new Response(stream, {
        headers: {
          'Content-Type': 'text/event-stream',
          'Cache-Control': 'no-cache',
          Connection: 'keep-alive',
        },
      });
    }

    if (req.method === 'POST' && url.pathname === '/presence') {
      const body = await req.json().catch(() => null) as { id?: string; focusedSession?: string | null; listening?: boolean } | null;
      const sub = body?.id ? subscribers.get(body.id) : undefined;
      if (!sub) return json({ error: 'unknown subscriber' }, 404);
      if (body && 'focusedSession' in body) sub.focusedSession = body.focusedSession ?? null;
      if (body && typeof body.listening === 'boolean') sub.listening = body.listening;
      return json({ ok: true, id: sub.id, focusedSession: sub.focusedSession, listening: sub.listening });
    }

    if (req.method === 'POST' && url.pathname === '/notify') {
      const body = await req.json().catch(() => null);
      const event = body ? translateLegacyNotify(body) : null;
      if (!event) return json({ error: 'missing message or language' }, 400);
      // Append to the producer stream: single pipeline, the tailer fans out.
      mkdirSync(dirname(STREAM_PATH), { recursive: true });
      appendFileSync(STREAM_PATH, JSON.stringify(event) + '\n', 'utf-8');
      return json({ ok: true, event: event.event });
    }

    return json({ error: 'not found' }, 404);
  },
});

startTailer();
console.log(`[broker] pulse-broker v${BROKER_VERSION} on http://localhost:${server.port}`);
console.log(`[broker] tailing ${STREAM_PATH}${REPLAY ? ' (replay from start)' : ' (live only)'}`);
