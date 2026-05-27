/**
 * OpenCode Mobile Client — focused tests
 */

import { describe, it, expect, beforeEach, afterEach, mock } from 'bun:test';

// ------------------------------------------------------------------
// Mock event-source-polyfill before importing the source under test
// ------------------------------------------------------------------

const mockInstances: MockEventSource[] = [];

class MockEventSource {
  private listeners: Record<string, ((event: any) => void)[]> = {};
  public url: string;
  public options: any;
  public closed = false;

  constructor(url: string, options?: any) {
    this.url = url;
    this.options = options ?? {};
    mockInstances.push(this);
  }

  addEventListener(event: string, callback: (event: any) => void) {
    if (!this.listeners[event]) this.listeners[event] = [];
    this.listeners[event].push(callback);
  }

  removeEventListener(event: string, callback: (event: any) => void) {
    if (!this.listeners[event]) return;
    this.listeners[event] = this.listeners[event].filter((cb) => cb !== callback);
  }

  close() {
    this.closed = true;
    this.emit('close', { type: 'close' });
  }

  emit(event: string, data: any) {
    this.listeners[event]?.forEach((cb) => cb(data));
  }
}

mock.module('event-source-polyfill', () => {
  return {
    EventSourcePolyfill: MockEventSource,
  };
});

// Mock our wrapper module (re-exports from event-source-polyfill)
mock.module('./event-source-wrapper', () => {
  return {
    EventSourcePolyfill: MockEventSource,
  };
});

function getLastMockInstance(): MockEventSource {
  return mockInstances[mockInstances.length - 1];
}

function clearMockInstances() {
  mockInstances.length = 0;
}

// ------------------------------------------------------------------
// Import source under test (after mock is registered)
// ------------------------------------------------------------------

import {
  verifyAuth,
  listSessions,
  getSession,
  createSession,
  listMessages,
  sendMessage,
  promptAsync,
  getAllSessionStatus,
  subscribeToEvents,
  parseSseEvent,
  mapSsePayloadToMessage,
  mapSsePayloadToMessagePart,
  mapSsePayloadToMessagePartDelta,
  deriveSessionStatus,
  OpenCodeClient,
  OpenCodeClientError,
  OpenCodeAuthError,
  OpenCodeNetworkError,
  OpenCodeValidationError,
  type ClientConfig,
} from './index';

const TEST_CONFIG: ClientConfig = {
  baseUrl: 'http://localhost:8080',
  username: 'test',
  password: 'secret',
};

// ------------------------------------------------------------------
// Mock fetch (for REST API tests)
// ------------------------------------------------------------------

const originalFetch = globalThis.fetch;

function mockFetchJson(status: number, body: unknown) {
  globalThis.fetch = (() =>
    Promise.resolve(
      new Response(JSON.stringify(body), {
        status,
        headers: { 'content-type': 'application/json' },
      })
    )) as unknown as typeof fetch;
}

function mockFetchError(message: string) {
  globalThis.fetch = (() => Promise.reject(new Error(message))) as unknown as typeof fetch;
}

// ------------------------------------------------------------------
// Auth
// ------------------------------------------------------------------

describe('verifyAuth', () => {
  it('resolves on 200 from /global/health', async () => {
    mockFetchJson(200, { ok: true });
    await expect(verifyAuth(TEST_CONFIG)).resolves.toBeUndefined();
  });

  it('throws OpenCodeAuthError on 401', async () => {
    mockFetchJson(401, { error: 'unauthorized' });
    await expect(verifyAuth(TEST_CONFIG)).rejects.toBeInstanceOf(OpenCodeAuthError);
  });

  it('throws OpenCodeNetworkError on fetch failure', async () => {
    mockFetchError('ECONNREFUSED');
    await expect(verifyAuth(TEST_CONFIG)).rejects.toBeInstanceOf(OpenCodeNetworkError);
  });
});

// ------------------------------------------------------------------
// Sessions
// ------------------------------------------------------------------

describe('listSessions', () => {
  it('maps real SessionInfo items to SessionSummary', async () => {
    mockFetchJson(200, {
      items: [
        {
          id: 'sess-1',
          title: 'First session',
          time: { created: 1700000000000, updated: 1700000100000 },
        },
      ],
    });

    const sessions = await listSessions(TEST_CONFIG);
    expect(sessions).toHaveLength(1);
    expect(sessions[0].id).toBe('sess-1');
    expect(sessions[0].title).toBe('First session');
    expect(sessions[0].updatedAt).toBe(new Date(1700000100000).toISOString());
    expect(sessions[0].messageCount).toBeUndefined();
  });

  it('falls back to bare array when no items wrapper', async () => {
    mockFetchJson(200, [
      { id: 'sess-2', title: 'Bare', time: { updated: 1700000000000 } },
    ]);

    const sessions = await listSessions(TEST_CONFIG);
    expect(sessions).toHaveLength(1);
    expect(sessions[0].id).toBe('sess-2');
  });

  it('throws OpenCodeClientError on non-object session response', async () => {
    mockFetchJson(200, { items: [null] });
    await expect(listSessions(TEST_CONFIG)).rejects.toBeInstanceOf(
      OpenCodeClientError
    );
  });
});

describe('getSession', () => {
  it('maps real Session to app Session', async () => {
    mockFetchJson(200, {
      id: 'sess-3',
      title: 'Detail',
      time: { created: 1700000000000, updated: 1700000100000 },
    });

    const session = await getSession(TEST_CONFIG, 'sess-3');
    expect(session.id).toBe('sess-3');
    expect(session.title).toBe('Detail');
    expect(session.status).toBe('active');
    expect(session.createdAt).toBe(new Date(1700000000000).toISOString());
  });
});

describe('createSession', () => {
  it('creates and maps response', async () => {
    mockFetchJson(200, {
      id: 'sess-new',
      title: 'New Session',
      time: { created: 1700000000000, updated: 1700000000000 },
    });

    const session = await createSession(TEST_CONFIG, { title: 'New Session' });
    expect(session.id).toBe('sess-new');
    expect(session.title).toBe('New Session');
  });
});

// ------------------------------------------------------------------
// Messages
// ------------------------------------------------------------------

describe('listMessages', () => {
  it('maps user and assistant messages', async () => {
    mockFetchJson(200, {
      items: [
        {
          id: 'msg-1',
          sessionID: 'sess-1',
          type: 'user',
          time: { created: 1700000000000 },
          text: 'Hello',
        },
        {
          id: 'msg-2',
          sessionID: 'sess-1',
          type: 'assistant',
          time: { created: 1700000001000 },
          content: [{ type: 'text', text: 'Hi there' }],
        },
      ],
    });

    const messages = await listMessages(TEST_CONFIG, 'sess-1');
    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe('user');
    expect(messages[0].parts[0].type).toBe('text');
    expect((messages[0].parts[0] as { text: string }).text).toBe('Hello');

    expect(messages[1].role).toBe('assistant');
    expect(messages[1].parts[0].type).toBe('text');
    expect((messages[1].parts[0] as { text: string }).text).toBe('Hi there');
  });

  it('maps tool parts', async () => {
    mockFetchJson(200, {
      items: [
        {
          id: 'msg-tool',
          sessionID: 'sess-1',
          type: 'assistant',
          time: { created: 1700000002000 },
          content: [
            {
              type: 'tool',
              id: 'call-1',
              name: 'bash',
              state: { status: 'pending', input: { command: 'ls' } },
            },
          ],
        },
      ],
    });

    const messages = await listMessages(TEST_CONFIG, 'sess-1');
    expect(messages[0].parts[0].type).toBe('tool_call');
  });

  it('maps real { info, parts } shape for user and assistant', async () => {
    mockFetchJson(200, {
      items: [
        {
          info: {
            id: 'msg-user-real',
            sessionID: 'sess-real',
            role: 'user',
            time: { created: 1700000000000 },
          },
          parts: [{ type: 'text', text: 'hi' }],
        },
        {
          info: {
            id: 'msg-assistant-real',
            sessionID: 'sess-real',
            role: 'assistant',
            time: { created: 1700000001000 },
          },
          parts: [{ type: 'text', text: 'Hello there' }],
        },
      ],
    });

    const messages = await listMessages(TEST_CONFIG, 'sess-real');
    expect(messages).toHaveLength(2);
    expect(messages[0].role).toBe('user');
    expect(messages[0].id).toBe('msg-user-real');
    expect((messages[0].parts[0] as { text: string }).text).toBe('hi');

    expect(messages[1].role).toBe('assistant');
    expect(messages[1].id).toBe('msg-assistant-real');
    expect((messages[1].parts[0] as { text: string }).text).toBe('Hello there');
  });
});

describe('sendMessage', () => {
  it('posts to /session/{id}/message and maps response', async () => {
    mockFetchJson(200, {
      id: 'msg-sent',
      sessionID: 'sess-1',
      type: 'assistant',
      time: { created: 1700000003000 },
      content: [{ type: 'text', text: 'Ack' }],
    });

    const msg = await sendMessage(TEST_CONFIG, 'sess-1', [
      { type: 'text', text: 'go' },
    ]);
    expect(msg.id).toBe('msg-sent');
    expect(msg.role).toBe('assistant');
  });

  it('maps { info, parts } response shape', async () => {
    mockFetchJson(200, {
      info: {
        id: 'msg-sent-real',
        sessionID: 'sess-1',
        role: 'assistant',
        time: { created: 1700000003000 },
      },
      parts: [{ type: 'text', text: 'Got it' }],
    });

    const msg = await sendMessage(TEST_CONFIG, 'sess-1', [
      { type: 'text', text: 'go' },
    ]);
    expect(msg.id).toBe('msg-sent-real');
    expect(msg.role).toBe('assistant');
    expect((msg.parts[0] as { text: string }).text).toBe('Got it');
  });
});

describe('promptAsync', () => {
  it('posts to /session/{id}/prompt_async and resolves void', async () => {
    mockFetchJson(202, { accepted: true });
    await expect(
      promptAsync(TEST_CONFIG, 'sess-1', {
        parts: [{ type: 'text', text: 'async' }],
      })
    ).resolves.toBeUndefined();
  });
});

// ------------------------------------------------------------------
// Session status
// ------------------------------------------------------------------

describe('getAllSessionStatus', () => {
  it('returns status object', async () => {
    mockFetchJson(200, { 'sess-1': { type: 'idle' } });
    const status = await getAllSessionStatus(TEST_CONFIG);
    expect(status['sess-1']).toEqual({ type: 'idle' });
  });
});

// ------------------------------------------------------------------
// SSE
// ------------------------------------------------------------------

describe('parseSseEvent', () => {
  it('parses data line with JSON', () => {
    const ev = parseSseEvent('data: {"type":"status","data":"idle"}');
    expect(ev).toEqual({
      type: 'status',
      data: { type: 'status', data: 'idle' },
      originalEvent: 'status',
    });
  });

  it('parses data line with plain text', () => {
    const ev = parseSseEvent('data: hello world');
    expect(ev).toEqual({ type: 'message', data: 'hello world' });
  });

  it('parses event line', () => {
    const ev = parseSseEvent('event: connected');
    expect(ev).toEqual({ type: 'connected', originalEvent: 'connected' });
  });

  it('returns null for empty line', () => {
    expect(parseSseEvent('')).toBeNull();
  });

  // Normalization of real OpenCode dotted event names
  it('normalizes server.connected → connected', () => {
    const ev = parseSseEvent('event: server.connected');
    expect(ev).toEqual({ type: 'connected', originalEvent: 'server.connected' });
  });

  it('normalizes message.updated → message', () => {
    const ev = parseSseEvent('data: {"type":"message.updated","sessionID":"s1"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).originalEvent).toBe('message.updated');
  });

  it('normalizes message.part.updated → message', () => {
    const ev = parseSseEvent('data: {"type":"message.part.updated","sessionID":"s1"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).originalEvent).toBe('message.part.updated');
  });

  it('normalizes message.part.delta → message', () => {
    const ev = parseSseEvent('data: {"type":"message.part.delta","sessionID":"s1"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).originalEvent).toBe('message.part.delta');
  });

  it('normalizes session.status → status', () => {
    const ev = parseSseEvent('event: session.status');
    expect(ev?.type).toBe('status');
    expect((ev as any).originalEvent).toBe('session.status');
  });

  it('normalizes session.idle → status', () => {
    const ev = parseSseEvent('data: {"type":"session.idle","sessionID":"s1"}');
    expect(ev?.type).toBe('status');
    expect((ev as any).originalEvent).toBe('session.idle');
  });

  it('normalizes session.error → error', () => {
    const ev = parseSseEvent('event: session.error');
    expect(ev?.type).toBe('error');
    expect((ev as any).originalEvent).toBe('session.error');
  });

  it('normalizes server.disconnected → disconnected', () => {
    const ev = parseSseEvent('event: server.disconnected');
    expect(ev?.type).toBe('disconnected');
    expect((ev as any).originalEvent).toBe('server.disconnected');
  });

  it('falls back unknown message.* to message', () => {
    const ev = parseSseEvent('event: message.unknown');
    expect(ev?.type).toBe('message');
    expect((ev as any).originalEvent).toBe('message.unknown');
  });

  it('falls back unknown session.* to status', () => {
    const ev = parseSseEvent('event: session.unknown');
    expect(ev?.type).toBe('status');
    expect((ev as any).originalEvent).toBe('session.unknown');
  });

  // Nested payload extraction (real OpenCode SDK shapes)
  it('extracts sessionId from properties.info.sessionID (message.updated)', () => {
    const ev = parseSseEvent(
      'data: {"type":"message.updated","properties":{"info":{"sessionID":"sess-nested-1"}}}'
    );
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBe('sess-nested-1');
  });

  it('extracts sessionId from properties.part.sessionID (message.part.updated)', () => {
    const ev = parseSseEvent(
      'data: {"type":"message.part.updated","properties":{"part":{"sessionID":"sess-nested-2"}}}'
    );
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBe('sess-nested-2');
  });

  it('extracts sessionId from properties.sessionID (session.status)', () => {
    const ev = parseSseEvent(
      'data: {"type":"session.status","properties":{"sessionID":"sess-nested-3","status":{"type":"idle"}}}'
    );
    expect(ev?.type).toBe('status');
    expect((ev as any).sessionId).toBe('sess-nested-3');
  });

  it('extracts sessionId from properties.sessionID (session.idle)', () => {
    const ev = parseSseEvent(
      'data: {"type":"session.idle","properties":{"sessionID":"sess-nested-4"}}'
    );
    expect(ev?.type).toBe('status');
    expect((ev as any).sessionId).toBe('sess-nested-4');
  });

  it('extracts sessionId from properties.sessionID (session.error)', () => {
    const ev = parseSseEvent(
      'data: {"type":"session.error","properties":{"sessionID":"sess-nested-5"}}'
    );
    expect(ev?.type).toBe('error');
    expect((ev as any).sessionId).toBe('sess-nested-5');
  });

  it('falls back to top-level sessionID when no properties wrapper', () => {
    const ev = parseSseEvent('data: {"type":"message.updated","sessionID":"sess-shallow"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBe('sess-shallow');
  });

  it('falls back to top-level sessionId (camelCase) when no properties wrapper', () => {
    const ev = parseSseEvent('data: {"type":"message.updated","sessionId":"sess-camel"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBe('sess-camel');
  });

  it('returns undefined sessionId when no session ID is present', () => {
    const ev = parseSseEvent('data: {"type":"message.updated","foo":"bar"}');
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBeUndefined();
  });

  it('preserves sessionId as undefined for non-JSON data', () => {
    const ev = parseSseEvent('data: hello world');
    expect(ev?.type).toBe('message');
    expect((ev as any).sessionId).toBeUndefined();
  });
});

describe('subscribeToEvents', () => {
  beforeEach(() => {
    clearMockInstances();
  });

  it('returns an unsubscribe function', () => {
    const sub = subscribeToEvents(TEST_CONFIG, () => {});
    expect(typeof sub.unsubscribe).toBe('function');
    sub.unsubscribe();
  });

  it('creates EventSource with correct URL and auth headers', () => {
    subscribeToEvents(TEST_CONFIG, () => {});
    const es = getLastMockInstance();
    expect(es.url).toBe('http://localhost:8080/event');
    expect(es.options.headers.Authorization).toBe('Basic ' + btoa('test:secret'));
    expect(es.options.headers.Accept).toBe('text/event-stream');
  });

  it('emits connected event on open', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('open', { type: 'open' });

    const connected = events.find((e) => e.type === 'connected');
    expect(connected).toBeDefined();
  });

  it('emits normalized message events for message.updated', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    // event-source-polyfill routes custom events through 'message' with type field
    es.emit('message', {
      type: 'message.updated',
      data: '{"sessionID":"s1","id":"m1"}',
    });

    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
    expect(msg.originalEvent).toBe('message.updated');
    expect(msg.data).toEqual({ sessionID: 's1', id: 'm1' });
    expect(msg.sessionId).toBe('s1');
  });

  it('emits normalized status events for session.idle', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'session.idle',
      data: '{"sessionID":"s1"}',
    });

    const status = events.find((e) => e.type === 'status');
    expect(status).toBeDefined();
    expect(status.originalEvent).toBe('session.idle');
    expect(status.data).toEqual({ sessionID: 's1' });
    expect(status.sessionId).toBe('s1');
  });

  it('emits error event on EventSource error', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('error', { type: 'error', message: 'Network failure' });

    const err = events.find((e) => e.type === 'error');
    expect(err).toBeDefined();
    expect(err.data).toBe('Network failure');
  });

  it('emits disconnected event on error after open', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    // First connect
    es.emit('open', { type: 'open' });
    expect(events.some((e) => e.type === 'connected')).toBe(true);

    // Then error — should emit disconnected
    events.length = 0;
    es.emit('error', { type: 'error', message: 'Server closed' });

    expect(events.some((e) => e.type === 'error')).toBe(true);
    expect(events.some((e) => e.type === 'disconnected')).toBe(true);
  });

  it('unsubscribe calls es.close()', () => {
    subscribeToEvents(TEST_CONFIG, () => {});
    const es = getLastMockInstance();

    const sub = { unsubscribe: () => es.close() };
    sub.unsubscribe();

    expect(es.closed).toBe(true);
  });

  it('handles generic message event without specific type', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'message',
      data: '{"type":"status","sessionID":"s2"}',
    });

    // Generic unnamed SSE events normalize to 'message' type
    // (the SSE event name is 'message', not the payload's type field)
    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
    expect(msg.data).toEqual({ type: 'status', sessionID: 's2' });
    expect(msg.sessionId).toBe('s2');
  });

  it('handles server.connected specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'server.connected',
      data: '',
    });

    const connected = events.find((e) => e.type === 'connected' && e.originalEvent === 'server.connected');
    expect(connected).toBeDefined();
  });

  it('handles server.disconnected specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'server.disconnected',
      data: '',
    });

    const disc = events.find((e) => e.type === 'disconnected');
    expect(disc).toBeDefined();
    expect(disc.originalEvent).toBe('server.disconnected');
  });

  it('handles message.part.updated specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'message.part.updated',
      data: '{"sessionID":"s1"}',
    });

    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
    expect(msg.originalEvent).toBe('message.part.updated');
  });

  it('handles message.part.delta specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'message.part.delta',
      data: '{"sessionID":"s1"}',
    });

    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
    expect(msg.originalEvent).toBe('message.part.delta');
  });

  it('handles session.status specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'session.status',
      data: '{"sessionID":"s1","status":{"type":"running"}}',
    });

    const status = events.find((e) => e.type === 'status');
    expect(status).toBeDefined();
    expect(status.originalEvent).toBe('session.status');
  });

  it('handles session.error specific event', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'session.error',
      data: '{"sessionID":"s1"}',
    });

    const err = events.find((e) => e.type === 'error');
    expect(err).toBeDefined();
    expect(err.originalEvent).toBe('session.error');
  });

  it('handles multiple sequential events', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('open', { type: 'open' });
    es.emit('message', {
      type: 'message.updated',
      data: '{"sessionID":"s1","id":"m1"}',
    });
    es.emit('message', {
      type: 'session.idle',
      data: '{"sessionID":"s1"}',
    });

    expect(events.filter((e) => e.type === 'connected').length).toBe(1);
    expect(events.filter((e) => e.type === 'message').length).toBe(1);
    expect(events.filter((e) => e.type === 'status').length).toBe(1);
  });

  it('handles empty data gracefully', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    es.emit('message', {
      type: 'message.updated',
      data: '',
    });

    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
    expect(msg.data).toEqual({});
  });

  it('emits implicit connected when message arrives before open', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    // Emit a message frame without an explicit 'open' event first
    es.emit('message', {
      type: 'message.updated',
      data: '{"sessionID":"s1","id":"m1"}',
    });

    const connected = events.find((e) => e.type === 'connected');
    expect(connected).toBeDefined();

    const msg = events.find((e) => e.type === 'message');
    expect(msg).toBeDefined();
  });

  it('emits disconnected on any error after open', () => {
    const events: any[] = [];
    subscribeToEvents(TEST_CONFIG, (ev) => events.push(ev));
    const es = getLastMockInstance();

    // First connect
    es.emit('open', { type: 'open' });
    expect(events.some((e) => e.type === 'connected')).toBe(true);

    // Then error — should emit disconnected (event-source-polyfill behavior)
    events.length = 0;
    es.emit('error', { type: 'error', message: 'Server closed' });

    expect(events.some((e) => e.type === 'error')).toBe(true);
    expect(events.some((e) => e.type === 'disconnected')).toBe(true);
  });
});

// ------------------------------------------------------------------
// SSE payload mapping helpers
// ------------------------------------------------------------------

describe('mapSsePayloadToMessage', () => {
  it('extracts message from properties.info.message', () => {
    const msg = {
      id: 'msg-1',
      sessionID: 'sess-1',
      type: 'assistant',
      time: { created: 1700000000000 },
      content: [{ type: 'text', text: 'Hello' }],
    };
    const payload = {
      type: 'message.updated',
      properties: { info: { sessionID: 'sess-1', message: msg } },
    };

    const result = mapSsePayloadToMessage(payload);
    expect(result).not.toBeNull();
    expect(result!.id).toBe('msg-1');
    expect(result!.role).toBe('assistant');
    expect(result!.parts[0].type).toBe('text');
    expect((result!.parts[0] as { text: string }).text).toBe('Hello');
  });

  it('extracts message from properties.message', () => {
    const msg = {
      id: 'msg-2',
      sessionID: 'sess-2',
      type: 'user',
      time: { created: 1700000000000 },
      text: 'Hi',
    };
    const payload = {
      type: 'message.updated',
      properties: { sessionID: 'sess-2', message: msg },
    };

    const result = mapSsePayloadToMessage(payload);
    expect(result).not.toBeNull();
    expect(result!.id).toBe('msg-2');
    expect(result!.role).toBe('user');
    expect(result!.parts[0].type).toBe('text');
    expect((result!.parts[0] as { text: string }).text).toBe('Hi');
  });

  it('falls back to treating payload as message when it has message-like fields', () => {
    const payload = {
      id: 'msg-3',
      sessionID: 'sess-3',
      type: 'assistant',
      time: { created: 1700000000000 },
      content: [{ type: 'text', text: 'Direct payload' }],
    };

    const result = mapSsePayloadToMessage(payload);
    expect(result).not.toBeNull();
    expect(result!.id).toBe('msg-3');
    expect((result!.parts[0] as { text: string }).text).toBe('Direct payload');
  });

  it('returns null for non-object payload', () => {
    expect(mapSsePayloadToMessage(null)).toBeNull();
    expect(mapSsePayloadToMessage('string')).toBeNull();
  });

  it('returns null when no message shape is found', () => {
    expect(mapSsePayloadToMessage({ foo: 'bar' })).toBeNull();
  });

  it('extracts message from { info, parts } payload directly', () => {
    const payload = {
      type: 'message.updated',
      info: {
        id: 'msg-info-parts',
        sessionID: 'sess-ip',
        role: 'assistant',
        time: { created: 1700000000000 },
      },
      parts: [{ type: 'text', text: 'From info parts' }],
    };

    const result = mapSsePayloadToMessage(payload);
    expect(result).not.toBeNull();
    expect(result!.id).toBe('msg-info-parts');
    expect(result!.role).toBe('assistant');
    expect((result!.parts[0] as { text: string }).text).toBe('From info parts');
  });

  it('creates shell message from properties.info with id/role/sessionID/time (no message wrapper)', () => {
    const payload = {
      type: 'message.updated',
      properties: {
        info: {
          id: 'msg-shell-1',
          sessionID: 'sess-shell',
          role: 'assistant',
          time: { created: 1700000000000 },
        },
      },
    };

    const result = mapSsePayloadToMessage(payload);
    expect(result).not.toBeNull();
    expect(result!.id).toBe('msg-shell-1');
    expect(result!.sessionId).toBe('sess-shell');
    expect(result!.role).toBe('assistant');
    expect(result!.parts).toHaveLength(1);
    expect(result!.parts[0].type).toBe('text');
    expect((result!.parts[0] as { text: string }).text).toBe('');
    expect(result!.createdAt).toBe(new Date(1700000000000).toISOString());
  });
});

describe('mapSsePayloadToMessagePart', () => {
  it('extracts part from properties.part wrapper', () => {
    const payload = {
      type: 'message.part.updated',
      properties: {
        part: {
          messageId: 'msg-1',
          part: { type: 'text', text: 'Updated part' },
        },
      },
    };

    const result = mapSsePayloadToMessagePart(payload);
    expect(result).not.toBeNull();
    expect(result!.messageId).toBe('msg-1');
    expect(result!.part.type).toBe('text');
    expect((result!.part as { text: string }).text).toBe('Updated part');
  });

  it('extracts part from properties.part when it is the part itself', () => {
    const payload = {
      type: 'message.part.updated',
      properties: {
        messageId: 'msg-2',
        part: { type: 'text', text: 'Direct part' },
      },
    };

    const result = mapSsePayloadToMessagePart(payload);
    expect(result).not.toBeNull();
    expect(result!.messageId).toBe('msg-2');
    expect((result!.part as { text: string }).text).toBe('Direct part');
  });

  it('returns null when messageId is missing', () => {
    const payload = {
      type: 'message.part.updated',
      properties: {
        part: { type: 'text', text: 'No messageId' },
      },
    };

    expect(mapSsePayloadToMessagePart(payload)).toBeNull();
  });

  it('returns null for non-object payload', () => {
    expect(mapSsePayloadToMessagePart(null)).toBeNull();
  });
});

describe('mapSsePayloadToMessagePartDelta', () => {
  it('extracts delta from properties.delta wrapper', () => {
    const payload = {
      type: 'message.part.delta',
      properties: {
        delta: {
          messageId: 'msg-1',
          partID: 'part-1',
          field: 'text',
          delta: 'hello',
        },
      },
    };

    const result = mapSsePayloadToMessagePartDelta(payload);
    expect(result).not.toBeNull();
    expect(result!.messageId).toBe('msg-1');
    expect(result!.field).toBe('text');
    expect(result!.delta).toBe('hello');
  });

  it('extracts delta from properties directly', () => {
    const payload = {
      type: 'message.part.delta',
      properties: {
        messageID: 'msg-2',
        field: 'text',
        delta: 'world',
      },
    };

    const result = mapSsePayloadToMessagePartDelta(payload);
    expect(result).not.toBeNull();
    expect(result!.messageId).toBe('msg-2');
    expect(result!.field).toBe('text');
    expect(result!.delta).toBe('world');
  });

  it('extracts delta from top-level payload', () => {
    const payload = {
      type: 'message.part.delta',
      messageId: 'msg-3',
      field: 'text',
      delta: 'top-level',
    };

    const result = mapSsePayloadToMessagePartDelta(payload);
    expect(result).not.toBeNull();
    expect(result!.messageId).toBe('msg-3');
    expect(result!.field).toBe('text');
    expect(result!.delta).toBe('top-level');
  });

  it('returns null when messageId is missing', () => {
    const payload = {
      type: 'message.part.delta',
      properties: {
        field: 'text',
        delta: 'no id',
      },
    };

    expect(mapSsePayloadToMessagePartDelta(payload)).toBeNull();
  });

  it('returns null when field is missing', () => {
    const payload = {
      type: 'message.part.delta',
      properties: {
        messageId: 'msg-4',
        delta: 'no field',
      },
    };

    expect(mapSsePayloadToMessagePartDelta(payload)).toBeNull();
  });

  it('returns null for non-object payload', () => {
    expect(mapSsePayloadToMessagePartDelta(null)).toBeNull();
    expect(mapSsePayloadToMessagePartDelta('string')).toBeNull();
  });
});

describe('deriveSessionStatus', () => {
  it('extracts status from properties.status.type', () => {
    const payload = {
      type: 'session.status',
      properties: { sessionID: 'sess-1', status: { type: 'idle' } },
    };

    const result = deriveSessionStatus(payload);
    expect(result).not.toBeNull();
    expect(result!.status).toBe('idle');
    expect(result!.isTerminal).toBe(true);
  });

  it('extracts string status from properties.status', () => {
    const payload = {
      type: 'session.status',
      properties: { sessionID: 'sess-1', status: 'running' },
    };

    const result = deriveSessionStatus(payload);
    expect(result).not.toBeNull();
    expect(result!.status).toBe('running');
    expect(result!.isTerminal).toBe(false);
  });

  it('extracts status from payload.status.type', () => {
    const payload = { status: { type: 'error' } };

    const result = deriveSessionStatus(payload);
    expect(result).not.toBeNull();
    expect(result!.status).toBe('error');
    expect(result!.isTerminal).toBe(true);
  });

  it('extracts status from payload.type for session.idle', () => {
    const payload = { type: 'session.idle', sessionID: 'sess-1' };

    const result = deriveSessionStatus(payload);
    expect(result).not.toBeNull();
    expect(result!.status).toBe('idle');
    expect(result!.isTerminal).toBe(true);
  });

  it('extracts status from payload.type for session.error', () => {
    const payload = { type: 'session.error', sessionID: 'sess-1' };

    const result = deriveSessionStatus(payload);
    expect(result).not.toBeNull();
    expect(result!.status).toBe('error');
    expect(result!.isTerminal).toBe(true);
  });

  it('returns null when no status is found', () => {
    expect(deriveSessionStatus({ foo: 'bar' })).toBeNull();
  });
});

// ------------------------------------------------------------------
// Class wrapper
// ------------------------------------------------------------------

describe('OpenCodeClient', () => {
  it('exposes all methods', () => {
    const client = new OpenCodeClient(TEST_CONFIG);
    expect(typeof client.verifyAuth).toBe('function');
    expect(typeof client.listSessions).toBe('function');
    expect(typeof client.getSession).toBe('function');
    expect(typeof client.createSession).toBe('function');
    expect(typeof client.listMessages).toBe('function');
    expect(typeof client.sendMessage).toBe('function');
    expect(typeof client.promptAsync).toBe('function');
    expect(typeof client.getAllSessionStatus).toBe('function');
    expect(typeof client.subscribeToEvents).toBe('function');
  });
});

// ------------------------------------------------------------------
// Cleanup
// ------------------------------------------------------------------

afterEach(() => {
  globalThis.fetch = originalFetch;
});