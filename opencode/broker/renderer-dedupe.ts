/**
 * Persistent, bounded dedupe ledger for the desktop renderer.
 *
 * Keyed by the broker's `dedupe_key` (see dedupeKey() in broker-lib.ts), it
 * survives renderer/broker restarts so that reconnects, /recent replay, and
 * crashes never re-speak or re-notify an event the user already heard.
 *
 * Design notes:
 * - Insertion-ordered LRU (mirrors the mobile PulseReconciler + producer Set).
 * - Capacity MUST be >= the largest /recent `n` (ring buffer is 200), otherwise
 *   an evicted key could reappear via /recent and re-render. Enforced as a floor.
 * - Fail-open: any load/write error degrades to in-memory only; it must never
 *   block speech.
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'fs';
import { dirname, join } from 'path';
import { homedir } from 'os';

export const DEFAULT_SEEN_PATH = join(
  homedir(),
  '.config',
  'opencode',
  'PAI',
  'MEMORY',
  'STATE',
  'pulse-desktop-seen.json',
);

/** Floor so the set always covers a full /recent replay (ring buffer = 200). */
export const MIN_CAPACITY = 200;
const DEFAULT_CAPACITY = 1000;
const DEFAULT_FLUSH_MS = 2000;

export interface DedupeStore {
  /** Returns true if the key is fresh (not seen before) and records it. */
  markAndCheckFresh(key: string): boolean;
  /** Non-mutating membership test. */
  has(key: string): boolean;
  /** Persist immediately if dirty (atomic tmp+rename). */
  flush(): void;
  size(): number;
}

interface PersistShape {
  v: number;
  capacity: number;
  keys: string[];
}

export function createDedupeStore(opts: { path?: string; capacity?: number; flushMs?: number } = {}): DedupeStore {
  const path = opts.path ?? DEFAULT_SEEN_PATH;
  const capacity = Math.max(MIN_CAPACITY, opts.capacity ?? DEFAULT_CAPACITY);
  const flushMs = opts.flushMs ?? DEFAULT_FLUSH_MS;

  const seen = new Set<string>();
  const order: string[] = [];
  let dirty = false;
  let timer: ReturnType<typeof setTimeout> | null = null;

  // ── Load existing ledger (fail-open) ──
  try {
    if (existsSync(path)) {
      const parsed = JSON.parse(readFileSync(path, 'utf-8')) as Partial<PersistShape>;
      if (parsed && Array.isArray(parsed.keys)) {
        for (const key of parsed.keys) {
          if (typeof key === 'string' && !seen.has(key)) {
            seen.add(key);
            order.push(key);
          }
        }
        // Trim if a previously-larger file exceeds the current capacity.
        evict();
      }
    }
  } catch {
    // Corrupt/unreadable ledger → start empty.
  }

  function evict(): void {
    while (order.length > capacity) {
      const oldest = order.shift();
      if (oldest !== undefined) seen.delete(oldest);
    }
  }

  function scheduleFlush(): void {
    dirty = true;
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      flush();
    }, flushMs);
    // Don't keep the event loop alive solely for a pending flush.
    if (typeof timer === 'object' && timer && 'unref' in timer) {
      (timer as { unref: () => void }).unref();
    }
  }

  function flush(): void {
    if (!dirty) return;
    try {
      mkdirSync(dirname(path), { recursive: true });
      const tmp = `${path}.tmp-${process.pid}`;
      const body: PersistShape = { v: 1, capacity, keys: order };
      writeFileSync(tmp, JSON.stringify(body), 'utf-8');
      renameSync(tmp, path);
      dirty = false;
    } catch {
      // Keep state in memory; retry on the next mutation. Never throw.
    }
  }

  return {
    markAndCheckFresh(key: string): boolean {
      if (!key) return true; // never dedupe an empty key
      if (seen.has(key)) return false;
      seen.add(key);
      order.push(key);
      evict();
      scheduleFlush();
      return true;
    },
    has(key: string): boolean {
      return seen.has(key);
    },
    flush,
    size(): number {
      return order.length;
    },
  };
}
