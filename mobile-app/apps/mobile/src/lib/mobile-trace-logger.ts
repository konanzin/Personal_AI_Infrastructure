/**
 * Mobile Trace Logger
 *
 * Lightweight, temporary instrumentation for tracing SSE text loss.
 * All logs use console.log with [PAI_MOBILE_TRACE] prefix for adb logcat filtering.
 *
 * Toggle ENABLED to false to disable all trace output at build time.
 */

const ENABLED = true;

export type TraceLevel = 'sse' | 'mapper' | 'store' | 'render';

function formatValue(v: unknown): string {
  if (v === null) return 'null';
  if (v === undefined) return 'undef';
  if (typeof v === 'string') {
    if (v.length === 0) return '""';
    const truncated = v.length > 48 ? v.slice(0, 45) + '...' : v;
    return `"${truncated}"`;
  }
  if (typeof v === 'number') return String(v);
  if (typeof v === 'boolean') return String(v);
  if (Array.isArray(v)) return `[len=${v.length}]`;
  if (typeof v === 'object') {
    const keys = Object.keys(v as Record<string, unknown>);
    return `{${keys.length}k}`;
  }
  return String(v);
}

export function mobileTrace(
  level: TraceLevel,
  tag: string,
  data: Record<string, unknown>
): void {
  if (!ENABLED) return;

  const entries = Object.entries(data)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${formatValue(v)}`)
    .join(' ');

  // eslint-disable-next-line no-console
  console.log(`[PAI_MOBILE_TRACE] ${level.toUpperCase().padEnd(6)} | ${tag.padEnd(28)} | ${entries}`);
}

/**
 * Summarize a raw SSE payload for compact logging.
 * Returns a string describing shape without dumping full content.
 */
export function summarizePayload(payload: unknown): string {
  if (payload === null) return 'null';
  if (payload === undefined) return 'undef';
  if (typeof payload !== 'object') return `${typeof payload}:${String(payload).slice(0, 20)}`;

  const obj = payload as Record<string, unknown>;
  const keys = Object.keys(obj);

  const hasProperties = 'properties' in obj;
  const hasInfo = 'info' in obj;
  const partsValue = obj.parts;
  const hasParts = Array.isArray(partsValue);
  const hasMessage = 'message' in obj;
  const hasDelta = 'delta' in obj;
  const hasPart = 'part' in obj;
  const hasType = typeof obj.type === 'string' ? obj.type : '';

  const shapeHints: string[] = [];
  if (hasType) shapeHints.push(`type=${hasType}`);
  if (hasProperties) shapeHints.push('props');
  if (hasInfo) shapeHints.push('info');
  if (hasParts) shapeHints.push(`parts[${partsValue.length}]`);
  if (hasMessage) shapeHints.push('msg');
  if (hasDelta) shapeHints.push('delta');
  if (hasPart) shapeHints.push('part');
  if (keys.includes('sessionID') || keys.includes('sessionId')) shapeHints.push('sid');

  const extraKeys = keys.filter(
    (k) => !['type', 'properties', 'info', 'parts', 'message', 'delta', 'part', 'sessionID', 'sessionId'].includes(k)
  );
  if (extraKeys.length > 0) shapeHints.push(`+${extraKeys.length}k`);

  return shapeHints.length > 0 ? shapeHints.join(',') : `{${keys.length}k}`;
}

/**
 * Summarize message parts for compact logging.
 */
export function summarizeParts(parts: Array<{ type: string; text?: string }>): string {
  return parts
    .map((p, i) => {
      const type = p.type;
      const textLen = typeof p.text === 'string' ? p.text.length : 0;
      return `${i}:${type}${textLen > 0 ? `(${textLen})` : ''}`;
    })
    .join(',');
}
