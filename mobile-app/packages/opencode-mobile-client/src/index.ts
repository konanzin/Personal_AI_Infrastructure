/**
 * OpenCode Mobile Client
 *
 * Unified API client for the OpenCode Server.
 * Uses real OpenCode REST endpoints and maps server shapes into the
 * shared app types consumed by the mobile UI.
 *
 * Endpoints:
 *   GET  /global/health
 *   GET  /session
 *   POST /session
 *   GET  /session/{id}
 *   GET  /session/{id}/message
 *   POST /session/{id}/message
 *   POST /session/{id}/prompt_async
 *   GET  /session/status
 *   GET  /event  (SSE)
 */

import type {
  SessionSummary,
  Session,
  SessionMessage,
  MessagePart,
  TextPart,
  ToolCallPart,
  ToolResultPart,
  ErrorPart,
} from '@pai/shared-types';
import {
  validateSessionSummary,
  validateSession,
  validateSessionMessage,
  isArray,
} from '@pai/shared-schemas';
import type { SchemaResult } from '@pai/shared-schemas';
import { EventSourcePolyfill } from './event-source-wrapper';

// ------------------------------------------------------------------
// Configuration
// ------------------------------------------------------------------

export type ClientConfig = {
  baseUrl: string;
  username: string;
  password: string;
};

// ------------------------------------------------------------------
// Errors
// ------------------------------------------------------------------

export class OpenCodeClientError extends Error {
  constructor(
    message: string,
    public readonly statusCode?: number,
    public readonly responseBody?: string
  ) {
    super(message);
    this.name = 'OpenCodeClientError';
  }
}

export class OpenCodeAuthError extends OpenCodeClientError {
  constructor(message = 'Authentication failed') {
    super(message, 401);
    this.name = 'OpenCodeAuthError';
  }
}

export class OpenCodeNetworkError extends OpenCodeClientError {
  constructor(message = 'Network error') {
    super(message);
    this.name = 'OpenCodeNetworkError';
  }
}

export class OpenCodeValidationError extends OpenCodeClientError {
  constructor(
    message: string,
    public readonly validationErrors: string[]
  ) {
    super(message, 422);
    this.name = 'OpenCodeValidationError';
  }
}

// ------------------------------------------------------------------
// Instrumentation (temporary — remove after Samsung SSE debugging)
// ------------------------------------------------------------------

const TRACE_ENABLED = true;

function logMapper(
  tag: string,
  data: Record<string, string | number | boolean | undefined>
): void {
  if (!TRACE_ENABLED) return;
  const entries = Object.entries(data)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${v}`)
    .join(' ');
  // eslint-disable-next-line no-console
  console.log(`[PAI_MOBILE_TRACE] MAPPER | ${tag.padEnd(32)} | ${entries}`);
}

function logTransport(
  tag: string,
  data: Record<string, string | number | boolean | undefined>
): void {
  if (!TRACE_ENABLED) return;
  const entries = Object.entries(data)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${v}`)
    .join(' ');
  // eslint-disable-next-line no-console
  console.log(`[PAI_MOBILE_TRACE] TRANSPORT | ${tag.padEnd(28)} | ${entries}`);
}

// ------------------------------------------------------------------
// Internal request helper
// ------------------------------------------------------------------

function encodeBasicAuth(username: string, password: string): string {
  return 'Basic ' + btoa(`${username}:${password}`);
}

async function apiRequest<T>(
  config: ClientConfig,
  path: string,
  options: RequestInit = {}
): Promise<unknown> {
  const url = `${config.baseUrl.replace(/\/$/, '')}${path}`;
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    Authorization: encodeBasicAuth(config.username, config.password),
    ...(options.headers as Record<string, string> || {}),
  };

  let response: Response;
  try {
    response = await fetch(url, {
      ...options,
      headers,
    });
  } catch (err) {
    throw new OpenCodeNetworkError(
      err instanceof Error ? err.message : 'Network request failed'
    );
  }

  if (response.status === 401) {
    throw new OpenCodeAuthError();
  }

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    throw new OpenCodeClientError(
      `HTTP ${response.status}: ${response.statusText}`,
      response.status,
      body
    );
  }

  // Handle empty body (e.g., 204 No Content)
  const contentType = response.headers.get('content-type') || '';
  if (response.status === 204 || !contentType.includes('application/json')) {
    return null;
  }

  try {
    return await response.json();
  } catch {
    throw new OpenCodeClientError('Invalid JSON in response', response.status);
  }
}

// ------------------------------------------------------------------
// Response extraction helpers
// ------------------------------------------------------------------

function extractArray(raw: unknown, key: string): unknown[] {
  if (Array.isArray(raw)) return raw;
  if (isObject(raw) && Array.isArray((raw as Record<string, unknown>)[key])) {
    return (raw as Record<string, unknown>)[key] as unknown[];
  }
  throw new OpenCodeClientError(`Expected array or { ${key}: [...] } in response`);
}

function isObject(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

// ------------------------------------------------------------------
// Real OpenCode API → App type mappers
// ------------------------------------------------------------------

function mapTimestamp(ts: unknown): string {
  if (typeof ts === 'number') return new Date(ts).toISOString();
  if (typeof ts === 'string') return ts;
  return new Date().toISOString();
}

/**
 * Map a real OpenCode SessionInfo (from /session list) into the app's
 * SessionSummary shape.
 */
function mapSessionInfoToSummary(raw: unknown): SessionSummary {
  if (!isObject(raw)) {
    throw new OpenCodeClientError('Expected session object in list');
  }
  const timeObj = isObject(raw.time) ? raw.time : {};
  return {
    id: String(raw.id ?? ''),
    title: String(raw.title ?? ''),
    updatedAt: mapTimestamp(timeObj.updated),
  };
}

/**
 * Map a real OpenCode Session (from /session/{id}) into the app's Session shape.
 */
function mapServerSessionToSession(raw: unknown): Session {
  if (!isObject(raw)) {
    throw new OpenCodeClientError('Expected session object');
  }
  const timeObj = isObject(raw.time) ? raw.time : {};
  return {
    id: String(raw.id ?? ''),
    title: String(raw.title ?? ''),
    status: 'active',
    createdAt: mapTimestamp(timeObj.created),
    updatedAt: mapTimestamp(timeObj.updated),
    metadata: undefined,
  };
}

/**
 * Convert a real OpenCode message part into the app's MessagePart union.
 */
function mapServerPartToPart(part: unknown): MessagePart | null {
  if (!isObject(part)) return null;
  const type = String(part.type ?? '');

  switch (type) {
    case 'text': {
      return {
        type: 'text',
        text: String(part.text ?? ''),
      } as TextPart;
    }
    case 'tool': {
      const state = isObject(part.state) ? part.state : {};
      const status = String(state.status ?? '');
      if (status === 'pending' || status === 'running') {
        return {
          type: 'tool_call',
          toolName: String(part.name ?? ''),
          args: isObject(state.input) ? state.input : {},
          callId: String(part.id ?? ''),
        } as ToolCallPart;
      }
      return {
        type: 'tool_result',
        callId: String(part.id ?? ''),
        result: status === 'completed'
          ? (isObject(state.structured) ? state.structured : state.content)
          : state,
        error: status === 'error' ? String((state as Record<string, unknown>).error ?? '') : undefined,
      } as ToolResultPart;
    }
    case 'reasoning': {
      return {
        type: 'text',
        text: `[reasoning] ${String(part.text ?? '')}`,
      } as TextPart;
    }
    case 'file': {
      return {
        type: 'text',
        text: `[file: ${String(part.filename ?? part.url ?? '')}]`,
      } as TextPart;
    }
    case 'error': {
      return {
        type: 'error',
        message: String(part.message ?? ''),
        code: String((part as Record<string, unknown>).code ?? ''),
      } as ErrorPart;
    }
    default:
      return null;
  }
}

/**
 * Derive a SessionMessage from an SSE `message.updated` payload.
 *
 * Real OpenCode sends the message in various nested shapes; we probe
 * the most common paths and fall back to treating the whole payload
 * as the message object.
 */
export function mapSsePayloadToMessage(payload: unknown): SessionMessage | null {
  if (!isObject(payload)) {
    logMapper('mapSsePayloadToMessage', { result: 'null', reason: 'non-object' });
    return null;
  }

  const props = isObject(payload.properties) ? payload.properties : undefined;
  const info = props && isObject(props.info) ? props.info : undefined;

  // Path 1: properties.info.message (most common for message.updated)
  if (info && isObject(info.message)) {
    const msg = mapServerMessageToMessage(info.message);
    logMapper('mapSsePayloadToMessage', {
      result: msg ? 'full' : 'null',
      path: 'properties.info.message',
      msgId: msg?.id ?? '',
      role: msg?.role ?? '',
      partsCount: msg?.parts.length ?? 0,
    });
    return msg;
  }

  // Path 1b: properties.info with id/role/sessionID/time but no message wrapper
  // (SSE assistant shell-only start payload)
  if (info && typeof info.id === 'string' && typeof info.role === 'string') {
    const sessionId = String(info.sessionID ?? '');
    const role = info.role === 'user' || info.role === 'assistant' ? info.role : 'system';
    const timeObj = isObject(info.time) ? info.time : {};
    const shell: SessionMessage = {
      id: String(info.id),
      sessionId,
      role,
      parts: [{ type: 'text', text: '' } as TextPart],
      createdAt: mapTimestamp(timeObj.created),
    };
    logMapper('mapSsePayloadToMessage', {
      result: 'shell',
      path: 'properties.info.shell',
      msgId: shell.id,
      role: shell.role,
    });
    return shell;
  }

  // Path 2: properties.message
  if (props && isObject(props.message)) {
    const msg = mapServerMessageToMessage(props.message);
    logMapper('mapSsePayloadToMessage', {
      result: msg ? 'full' : 'null',
      path: 'properties.message',
      msgId: msg?.id ?? '',
      role: msg?.role ?? '',
      partsCount: msg?.parts.length ?? 0,
    });
    return msg;
  }

  // Path 3: payload has { info, parts } shape (real mobile session messages)
  if (isObject(payload.info) && Array.isArray(payload.parts)) {
    const msg = mapServerMessageToMessage(payload);
    logMapper('mapSsePayloadToMessage', {
      result: msg ? 'full' : 'null',
      path: 'payload.info+parts',
      msgId: msg?.id ?? '',
      role: msg?.role ?? '',
      partsCount: msg?.parts.length ?? 0,
    });
    return msg;
  }

  // Path 4: payload has message-like fields (id, type, content/text)
  if (typeof payload.id === 'string' && (typeof payload.type === 'string' || Array.isArray(payload.content) || typeof payload.text === 'string')) {
    const msg = mapServerMessageToMessage(payload);
    logMapper('mapSsePayloadToMessage', {
      result: msg ? 'full' : 'null',
      path: 'payload.direct',
      msgId: msg?.id ?? '',
      role: msg?.role ?? '',
      partsCount: msg?.parts.length ?? 0,
    });
    return msg;
  }

  logMapper('mapSsePayloadToMessage', { result: 'null', reason: 'no-path-matched' });
  return null;
}

/**
 * Derive a MessagePart and its parent messageId from an SSE
 * `message.part.updated` payload.
 */
export function mapSsePayloadToMessagePart(payload: unknown): { messageId: string; part: MessagePart } | null {
  if (!isObject(payload)) {
    logMapper('mapSsePayloadToMessagePart', { result: 'null', reason: 'non-object' });
    return null;
  }

  const props = isObject(payload.properties) ? payload.properties : undefined;
  if (!props) {
    logMapper('mapSsePayloadToMessagePart', { result: 'null', reason: 'no-properties' });
    return null;
  }

  // Path 1: properties.part contains the part + messageId
  const partWrapper = isObject(props.part) ? props.part : undefined;
  if (partWrapper) {
    const messageId = String(partWrapper.messageId ?? partWrapper.messageID ?? '');
    const partObj = isObject(partWrapper.part) ? partWrapper.part : partWrapper;
    const mapped = mapServerPartToPart(partObj);
    if (mapped && messageId) {
      logMapper('mapSsePayloadToMessagePart', {
        result: 'part',
        path: 'properties.part.wrapper',
        messageId,
        partType: mapped.type,
      });
      return { messageId, part: mapped };
    }
  }

  // Path 2: properties contains part directly + messageId at top level of properties
  const messageId = String(props.messageId ?? props.messageID ?? payload.messageId ?? payload.messageID ?? '');
  const partObj = isObject(props.part) ? props.part : undefined;
  if (partObj && messageId) {
    const mapped = mapServerPartToPart(partObj);
    if (mapped) {
      logMapper('mapSsePayloadToMessagePart', {
        result: 'part',
        path: 'properties.part.direct',
        messageId,
        partType: mapped.type,
      });
      return { messageId, part: mapped };
    }
  }

  logMapper('mapSsePayloadToMessagePart', { result: 'null', reason: 'no-match' });
  return null;
}

/**
 * Derive a text delta and its parent messageId from an SSE
 * `message.part.delta` payload.
 *
 * Real OpenCode sends: { messageID, partID, field: "text", delta: "..." }
 * We probe multiple nested paths for compatibility.
 */
export function mapSsePayloadToMessagePartDelta(
  payload: unknown
): { messageId: string; field: string; delta: string } | null {
  if (!isObject(payload)) {
    logMapper('mapSsePayloadToMessagePartDelta', { result: 'null', reason: 'non-object' });
    return null;
  }

  const props = isObject(payload.properties) ? payload.properties : undefined;

  // Path 1: properties.delta contains the delta fields
  const deltaWrapper = isObject(props?.delta) ? props.delta : undefined;
  if (deltaWrapper) {
    const messageId = String(deltaWrapper.messageId ?? deltaWrapper.messageID ?? '');
    const field = String(deltaWrapper.field ?? '');
    const delta = String(deltaWrapper.delta ?? '');
    if (messageId && field) {
      logMapper('mapSsePayloadToMessagePartDelta', {
        result: 'delta',
        path: 'properties.delta.wrapper',
        messageId,
        field,
        deltaLen: delta.length,
      });
      return { messageId, field, delta };
    }
  }

  // Path 2: properties contains delta fields directly
  const messageId = String(
    props?.messageId ?? props?.messageID ?? payload.messageId ?? payload.messageID ?? ''
  );
  const field = String(props?.field ?? payload.field ?? '');
  const delta = String(props?.delta ?? payload.delta ?? '');
  if (messageId && field) {
    logMapper('mapSsePayloadToMessagePartDelta', {
      result: 'delta',
      path: 'properties.direct',
      messageId,
      field,
      deltaLen: delta.length,
    });
    return { messageId, field, delta };
  }

  logMapper('mapSsePayloadToMessagePartDelta', { result: 'null', reason: 'no-match' });
  return null;
}

/**
 * Derive session status info from SSE status/idle/error payloads.
 */
export function deriveSessionStatus(payload: unknown): { status: string; isTerminal: boolean } | null {
  if (!isObject(payload)) return null;

  const props = isObject(payload.properties) ? payload.properties : undefined;

  // Probe multiple nested paths for status
  let status: string | undefined;

  // Path 1: properties.status.type
  if (props && isObject(props.status) && typeof props.status.type === 'string') {
    status = props.status.type;
  }
  // Path 2: properties.status (string)
  else if (props && typeof props.status === 'string') {
    status = props.status;
  }
  // Path 3: payload.status.type
  else if (isObject(payload.status) && typeof payload.status.type === 'string') {
    status = payload.status.type;
  }
  // Path 4: payload.status (string)
  else if (typeof payload.status === 'string') {
    status = payload.status;
  }
  // Path 5: payload.type itself (for session.idle, session.error)
  else if (typeof payload.type === 'string' && (payload.type === 'session.idle' || payload.type === 'session.error')) {
    status = payload.type === 'session.idle' ? 'idle' : 'error';
  }

  if (!status) return null;

  const isTerminal = status === 'idle' || status === 'error';
  return { status, isTerminal };
}

/**
 * Map a real OpenCode SessionMessage into the app's SessionMessage shape.
 */
function mapServerMessageToMessage(raw: unknown): SessionMessage {
  if (!isObject(raw)) {
    throw new OpenCodeClientError('Expected message object');
  }

  const msgType = String(raw.type ?? '');
  const timeObj = isObject(raw.time) ? raw.time : {};
  const sessionId = String(raw.sessionID ?? '');
  const id = String(raw.id ?? '');
  const createdAt = mapTimestamp(timeObj.created);

  // Real OpenCode { info, parts } shape (newer API responses)
  const info = isObject(raw.info) ? raw.info : undefined;
  if (info && Array.isArray(raw.parts)) {
    const role = String(info.role ?? '');
    const parts: MessagePart[] = [];
    for (const p of raw.parts) {
      const mapped = mapServerPartToPart(p);
      if (mapped) parts.push(mapped);
    }
    if (parts.length === 0) {
      parts.push({ type: 'text', text: '' } as TextPart);
    }
    const msgId = String(info.id ?? raw.id ?? '');
    const msgSessionId = String(info.sessionID ?? raw.sessionID ?? '');
    const msgTimeObj = isObject(info.time) ? info.time : {};
    const msgCreatedAt = mapTimestamp(msgTimeObj.created);
    return {
      id: msgId,
      sessionId: msgSessionId,
      role: role === 'user' || role === 'assistant' ? role : 'system',
      parts,
      createdAt: msgCreatedAt,
    };
  }

  // User message
  if (msgType === 'user') {
    const parts: MessagePart[] = [];
    if (typeof raw.text === 'string' && raw.text) {
      parts.push({ type: 'text', text: raw.text } as TextPart);
    }
    const files = Array.isArray(raw.files) ? raw.files : [];
    for (const f of files) {
      if (isObject(f)) {
        parts.push({
          type: 'text',
          text: `[file: ${String(f.name ?? f.url ?? '')}]`,
        } as TextPart);
      }
    }
    if (parts.length === 0) {
      parts.push({ type: 'text', text: '' } as TextPart);
    }
    return { id, sessionId, role: 'user', parts, createdAt };
  }

  // Assistant message
  if (msgType === 'assistant') {
    const content = Array.isArray(raw.content) ? raw.content : [];
    const parts: MessagePart[] = [];
    for (const c of content) {
      const mapped = mapServerPartToPart(c);
      if (mapped) parts.push(mapped);
    }
    if (parts.length === 0) {
      parts.push({ type: 'text', text: '' } as TextPart);
    }
    return { id, sessionId, role: 'assistant', parts, createdAt };
  }

  // Shell message
  if (msgType === 'shell') {
    const command = String(raw.command ?? '');
    const output = String(raw.output ?? '');
    return {
      id,
      sessionId,
      role: 'assistant',
      parts: [
        { type: 'text', text: `\`\`\`bash\n$ ${command}\n${output}\n\`\`\`` } as TextPart,
      ],
      createdAt,
    };
  }

  // Synthetic / compaction / other — fall back to text
  const text = typeof (raw as Record<string, unknown>).text === 'string'
    ? String((raw as Record<string, unknown>).text)
    : `[${msgType}]`;
  return {
    id,
    sessionId,
    role: 'system',
    parts: [{ type: 'text', text } as TextPart],
    createdAt,
  };
}

// ------------------------------------------------------------------
// Auth
// ------------------------------------------------------------------

/**
 * Verify credentials by hitting the health endpoint.
 * Real endpoint: GET /global/health
 */
export async function verifyAuth(config: ClientConfig): Promise<void> {
  await apiRequest(config, '/global/health', { method: 'GET' });
}

// ------------------------------------------------------------------
// Sessions
// ------------------------------------------------------------------

/**
 * List all sessions.
 * Real endpoint: GET /session
 * Response: { items: SessionInfo[] } or SessionInfo[]
 */
export async function listSessions(
  config: ClientConfig
): Promise<SessionSummary[]> {
  const raw = await apiRequest<unknown>(config, '/session', { method: 'GET' });
  const sessions = extractArray(raw, 'items');

  const mapped = sessions.map((item) => mapSessionInfoToSummary(item));

  const results = mapped.map((item) => validateSessionSummary(item));
  const failures = results.filter((r) => !r.success);
  if (failures.length > 0) {
    const errors = failures.flatMap((f) => f.errors);
    throw new OpenCodeValidationError('Invalid session summary from server', errors);
  }

  return results.map((r) => (r as Extract<typeof r, { success: true }>).data);
}

/**
 * Get a single session by ID.
 * Real endpoint: GET /session/{id}
 */
export async function getSession(
  config: ClientConfig,
  sessionId: string
): Promise<Session> {
  const raw = await apiRequest<unknown>(
    config,
    `/session/${encodeURIComponent(sessionId)}`,
    { method: 'GET' }
  );

  const mapped = mapServerSessionToSession(raw);
  const result = validateSession(mapped);
  if (!result.success) {
    throw new OpenCodeValidationError('Invalid session from server', result.errors);
  }
  return result.data;
}

/**
 * Create a new session.
 * Real endpoint: POST /session with { title?, agent?, model?, ... }
 */
export async function createSession(
  config: ClientConfig,
  options: { title?: string } = {}
): Promise<Session> {
  const raw = await apiRequest<unknown>(config, '/session', {
    method: 'POST',
    body: JSON.stringify(options),
  });

  const mapped = mapServerSessionToSession(raw);
  const result = validateSession(mapped);
  if (!result.success) {
    throw new OpenCodeValidationError('Invalid session from server on create', result.errors);
  }
  return result.data;
}

// ------------------------------------------------------------------
// Messages
// ------------------------------------------------------------------

/**
 * List messages for a session.
 * Real endpoint: GET /session/{id}/message
 * Response: { items: SessionMessage[] } or SessionMessage[]
 */
export async function listMessages(
  config: ClientConfig,
  sessionId: string
): Promise<SessionMessage[]> {
  const raw = await apiRequest<unknown>(
    config,
    `/session/${encodeURIComponent(sessionId)}/message`,
    { method: 'GET' }
  );

  const messages = extractArray(raw, 'items');
  const mapped = messages.map((item) => mapServerMessageToMessage(item));

  const results = mapped.map((item) => validateSessionMessage(item));
  const failures = results.filter((r) => !r.success);
  if (failures.length > 0) {
    const errors = failures.flatMap((f) => f.errors);
    throw new OpenCodeValidationError('Invalid message from server', errors);
  }

  return results.map((r) => (r as Extract<typeof r, { success: true }>).data);
}

/**
 * Send a message to a session.
 * Real endpoint: POST /session/{id}/message with { parts: MessagePart[] }
 */
export async function sendMessage(
  config: ClientConfig,
  sessionId: string,
  parts: SessionMessage['parts']
): Promise<SessionMessage> {
  const raw = await apiRequest<unknown>(
    config,
    `/session/${encodeURIComponent(sessionId)}/message`,
    {
      method: 'POST',
      body: JSON.stringify({ parts }),
    }
  );

  const mapped = mapServerMessageToMessage(raw);
  const result = validateSessionMessage(mapped);
  if (!result.success) {
    throw new OpenCodeValidationError('Invalid message from server on send', result.errors);
  }
  return result.data;
}

/**
 * Send an async prompt to a session (non-blocking).
 * Real endpoint: POST /session/{id}/prompt_async
 */
export async function promptAsync(
  config: ClientConfig,
  sessionId: string,
  options: {
    parts: SessionMessage['parts'];
    agent?: string;
    model?: string;
    noReply?: boolean;
  }
): Promise<void> {
  await apiRequest<unknown>(
    config,
    `/session/${encodeURIComponent(sessionId)}/prompt_async`,
    {
      method: 'POST',
      body: JSON.stringify(options),
    }
  );
}

// ------------------------------------------------------------------
// Session status
// ------------------------------------------------------------------

/**
 * Retrieve the current status of all sessions.
 * Real endpoint: GET /session/status
 */
export async function getAllSessionStatus(
  config: ClientConfig
): Promise<Record<string, unknown>> {
  const raw = await apiRequest<unknown>(config, '/session/status', { method: 'GET' });
  return isObject(raw) ? raw : {};
}

// ------------------------------------------------------------------
// SSE Events
// ------------------------------------------------------------------

export type OpenCodeEvent =
  | { type: 'message'; data: unknown; sessionId?: string; originalEvent?: string }
  | { type: 'status'; data: unknown; sessionId?: string; originalEvent?: string }
  | { type: 'error'; data: unknown; sessionId?: string; originalEvent?: string }
  | { type: 'connected'; data?: unknown; sessionId?: string; originalEvent?: string }
  | { type: 'disconnected'; data?: unknown; sessionId?: string; originalEvent?: string };

export type EventCallback = (event: OpenCodeEvent) => void;

export interface EventSubscription {
  unsubscribe: () => void;
}

// ------------------------------------------------------------------
// SSE event normalization
// ------------------------------------------------------------------

/**
 * Extract a session ID from the many possible nested shapes real
 * OpenCode payloads use.
 *
 * Supported paths (in priority order):
 *   - properties.info.sessionID    (message.updated)
 *   - properties.part.sessionID    (message.part.updated)
 *   - properties.sessionID         (session.status, session.idle, session.error)
 *   - sessionID / sessionId        (top-level fallback)
 */
function extractSessionIdFromPayload(parsed: unknown): string | undefined {
  if (!isObject(parsed)) return undefined;

  const props = isObject(parsed.properties) ? parsed.properties : undefined;
  if (props) {
    const info = isObject(props.info) ? props.info : undefined;
    if (info && typeof info.sessionID === 'string') {
      return info.sessionID;
    }

    const part = isObject(props.part) ? props.part : undefined;
    if (part && typeof part.sessionID === 'string') {
      return part.sessionID;
    }

    if (typeof props.sessionID === 'string') {
      return props.sessionID;
    }
  }

  if (typeof parsed.sessionID === 'string') {
    return parsed.sessionID;
  }
  if (typeof parsed.sessionId === 'string') {
    return parsed.sessionId;
  }

  return undefined;
}

function normalizeEventType(raw: string): OpenCodeEvent['type'] {
  switch (raw) {
    case 'server.connected':
      return 'connected';
    case 'message.updated':
    case 'message.part.updated':
    case 'message.part.delta':
      return 'message';
    case 'session.status':
    case 'session.idle':
    case 'status':
      return 'status';
    case 'session.error':
    case 'error':
      return 'error';
    case 'server.disconnected':
      return 'disconnected';
    default:
      // Forward-compatibility heuristics
      if (raw.startsWith('message.')) return 'message';
      if (raw.startsWith('session.')) return 'status';
      if (raw === 'connected' || raw === 'disconnected') return raw;
      return 'message';
  }
}

function buildOpenCodeEvent(eventName: string, data: string): OpenCodeEvent | null {
  if (!eventName && !data) return null;

  const rawType = eventName || '';
  const normalizedType = normalizeEventType(rawType);

  if (!data) {
    if (normalizedType === 'connected' || normalizedType === 'disconnected') {
      return { type: normalizedType, originalEvent: rawType || undefined };
    }
    return { type: normalizedType, data: {}, originalEvent: rawType || undefined };
  }

  try {
    const parsed = JSON.parse(data);
    return {
      type: normalizedType,
      data: parsed,
      sessionId: extractSessionIdFromPayload(parsed),
      originalEvent: rawType || undefined,
    };
  } catch {
    return {
      type: normalizedType,
      data,
      originalEvent: rawType || undefined,
    };
  }
}

/**
 * Parse a single SSE event line into an OpenCodeEvent.
 *
 * Note: this handles individual `data:` or `event:` lines for backward
 * compatibility. In full SSE streams subscribeToEvents accumulates both
 * fields before emitting a single event.
 */
export function parseSseEvent(line: string): OpenCodeEvent | null {
  if (line.startsWith('data: ')) {
    const payload = line.slice(6);
    try {
      const parsed = JSON.parse(payload);
      const rawType = typeof parsed.type === 'string' ? parsed.type : '';
      const normalizedType = normalizeEventType(rawType);
      return {
        type: normalizedType,
        data: parsed,
        sessionId: extractSessionIdFromPayload(parsed),
        originalEvent: rawType || undefined,
      };
    } catch {
      return { type: 'message', data: payload };
    }
  }
  if (line.startsWith('event: ')) {
    const eventType = line.slice(7);
    const normalizedType = normalizeEventType(eventType);
    if (normalizedType === 'connected' || normalizedType === 'disconnected') {
      return { type: normalizedType, originalEvent: eventType };
    }
    return {
      type: normalizedType,
      data: { event: eventType },
      originalEvent: eventType,
    };
  }
  return null;
}

/**
 * Subscribe to the OpenCode event stream.
 * Real endpoint: GET /event (SSE)
 *
 * Uses `event-source-polyfill` (standard, 1.49M weekly downloads)
 * because `react-native-sse` has critical bugs in Expo Go / Hermes / Android
 * where XMLHttpRequest.DONE is undefined, preventing the open event.
 */
const SSE_HANDSHAKE_TIMEOUT_MS = 5000;

export function subscribeToEvents(
  config: ClientConfig,
  onEvent: EventCallback
): EventSubscription {
  const url = `${config.baseUrl.replace(/\/$/, '')}/event`;
  const authHeader = encodeBasicAuth(config.username, config.password);

  logTransport('subscribeToEvents', { baseUrl: config.baseUrl, url });

  // ── DIAGNOSTIC: manual XMLHttpRequest probe ──
  // This tells us whether the problem is the library or the infrastructure.
  const XHR = (globalThis as any).XMLHttpRequest;
  const probe = new XHR();
  probe.open('GET', url, true);
  probe.setRequestHeader('Accept', 'text/event-stream');
  probe.setRequestHeader('Authorization', authHeader);
  probe.onreadystatechange = () => {
    logTransport('xhrProbe', {
      readyState: probe.readyState,
      status: probe.status,
      statusText: probe.statusText,
      responseLen: probe.responseText?.length ?? 0,
    });
  };
  probe.onerror = () => {
    logTransport('xhrProbeError', { status: probe.status, statusText: probe.statusText });
  };
  probe.send();

  let isOpen = false;
  let handshakeTimer: ReturnType<typeof setTimeout> | null = null;
  let debugInterval: ReturnType<typeof setInterval> | null = null;

  const es = new EventSourcePolyfill(url, {
    headers: {
      Accept: 'text/event-stream',
      Authorization: authHeader,
    },
    withCredentials: false,
  });

  logTransport('subscriptionCreated', { url, readyState: es.readyState, withCredentials: es.withCredentials });

  // Debug: monitor EventSource state every second for first 10s
  let debugCount = 0;
  debugInterval = setInterval(() => {
    debugCount++;
    if (debugCount > 10 || isOpen) {
      clearInterval(debugInterval!);
      return;
    }
    logTransport('debugState', {
      url,
      readyState: es.readyState,
      isOpen,
      count: debugCount,
    });
  }, 1000);

  const markConnected = () => {
    if (isOpen) return;
    isOpen = true;
    if (handshakeTimer) {
      clearTimeout(handshakeTimer);
      handshakeTimer = null;
    }
    logTransport('connected', { url });
    onEvent({ type: 'connected', data: {} });
  };

  const handleSseEvent = (event: { type: string; data?: string | null }) => {
    if (!isOpen) {
      logTransport('implicitOpen', { url, reason: 'frame-before-open', event: event.type });
      markConnected();
    }

    const eventName = event.type || '';
    const data = event.data || '';
    logTransport('frame', { event: eventName, dataLen: data.length });
    const ev = buildOpenCodeEvent(eventName, data);
    if (ev) onEvent(ev);
  };

  es.addEventListener('open', () => {
    markConnected();
  });

  es.addEventListener('message', handleSseEvent);

  es.addEventListener('error', (event: any) => {
    const msg = event?.error?.message || event?.message || 'EventSource error';
    logTransport('error', { message: msg });
    onEvent({ type: 'error', data: msg });

    if (isOpen) {
      isOpen = false;
      logTransport('disconnected', { url, reason: 'error' });
      onEvent({ type: 'disconnected', data: {} });
    }
  });

  handshakeTimer = setTimeout(() => {
    if (!isOpen) {
      logTransport('handshakeTimeout', {
        url,
        timeoutMs: SSE_HANDSHAKE_TIMEOUT_MS,
        note: 'open-never-fired-check-xhr-constants',
      });
    }
  }, SSE_HANDSHAKE_TIMEOUT_MS);

  return {
    unsubscribe: () => {
      logTransport('unsubscribe', { url });
      if (handshakeTimer) {
        clearTimeout(handshakeTimer);
        handshakeTimer = null;
      }
      if (debugInterval != null) {
        clearInterval(debugInterval);
        debugInterval = null;
      }
      es.close();
    },
  };
}

// ------------------------------------------------------------------
// Class wrapper (convenience — maintains stateful config)
// ------------------------------------------------------------------

export class OpenCodeClient {
  constructor(private config: ClientConfig) {}

  verifyAuth(): Promise<void> {
    return verifyAuth(this.config);
  }

  listSessions(): Promise<SessionSummary[]> {
    return listSessions(this.config);
  }

  getSession(sessionId: string): Promise<Session> {
    return getSession(this.config, sessionId);
  }

  createSession(options?: { title?: string }): Promise<Session> {
    return createSession(this.config, options);
  }

  listMessages(sessionId: string): Promise<SessionMessage[]> {
    return listMessages(this.config, sessionId);
  }

  sendMessage(sessionId: string, parts: SessionMessage['parts']): Promise<SessionMessage> {
    return sendMessage(this.config, sessionId, parts);
  }

  promptAsync(
    sessionId: string,
    options: {
      parts: SessionMessage['parts'];
      agent?: string;
      model?: string;
      noReply?: boolean;
    }
  ): Promise<void> {
    return promptAsync(this.config, sessionId, options);
  }

  getAllSessionStatus(): Promise<Record<string, unknown>> {
    return getAllSessionStatus(this.config);
  }

  subscribeToEvents(onEvent: EventCallback): EventSubscription {
    return subscribeToEvents(this.config, onEvent);
  }
}
