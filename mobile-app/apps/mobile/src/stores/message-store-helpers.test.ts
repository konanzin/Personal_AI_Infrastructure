import { describe, it, expect } from 'bun:test';
import type { SessionMessage, MessagePart } from '@pai/shared-types';
import {
  partsMatch,
  findMatchingPartIndex,
  isOptimisticMessage,
  canReconcileOptimistic,
  sortByCreatedAt,
  upsertMessageWithReconciliation,
  upsertPartWithDedup,
  applyTextDeltaToParts,
  RECONCILE_WINDOW_MS,
} from './message-store-helpers';

function makeMessage(overrides: Partial<SessionMessage> = {}): SessionMessage {
  return {
    id: 'msg-1',
    sessionId: 'sess-1',
    role: 'user',
    parts: [{ type: 'text', text: 'Hello' }],
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

// ------------------------------------------------------------------
// partsMatch
// ------------------------------------------------------------------

describe('partsMatch', () => {
  it('matches identical text parts', () => {
    const a: MessagePart = { type: 'text', text: 'hello' };
    const b: MessagePart = { type: 'text', text: 'hello' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('does not match text parts with different content', () => {
    const a: MessagePart = { type: 'text', text: 'hello' };
    const b: MessagePart = { type: 'text', text: 'world' };
    expect(partsMatch(a, b)).toBe(false);
  });

  it('matches tool_call parts by callId', () => {
    const a: MessagePart = { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' };
    const b: MessagePart = { type: 'tool_call', toolName: 'bash', args: { x: 1 }, callId: 'call-1' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('does not match tool_call parts with different callId', () => {
    const a: MessagePart = { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' };
    const b: MessagePart = { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-2' };
    expect(partsMatch(a, b)).toBe(false);
  });

  it('matches tool_result parts by callId', () => {
    const a: MessagePart = { type: 'tool_result', callId: 'call-1', result: 'ok' };
    const b: MessagePart = { type: 'tool_result', callId: 'call-1', result: 'ok' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('does not match parts of different types', () => {
    const a: MessagePart = { type: 'text', text: 'hello' };
    const b: MessagePart = { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' };
    expect(partsMatch(a, b)).toBe(false);
  });

  it('matches code parts by language and code', () => {
    const a: MessagePart = { type: 'code', language: 'ts', code: 'const x = 1;' };
    const b: MessagePart = { type: 'code', language: 'ts', code: 'const x = 1;' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('does not match code parts with different code', () => {
    const a: MessagePart = { type: 'code', language: 'ts', code: 'const x = 1;' };
    const b: MessagePart = { type: 'code', language: 'ts', code: 'const y = 2;' };
    expect(partsMatch(a, b)).toBe(false);
  });

  it('matches permission_request parts by requestId', () => {
    const a: MessagePart = { type: 'permission_request', requestId: 'req-1', action: 'read', resource: 'file', description: 'Read file' };
    const b: MessagePart = { type: 'permission_request', requestId: 'req-1', action: 'write', resource: 'dir', description: 'Write dir' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('matches question parts by questionId', () => {
    const a: MessagePart = { type: 'question', questionId: 'q-1', text: 'What?' };
    const b: MessagePart = { type: 'question', questionId: 'q-1', text: 'When?' };
    expect(partsMatch(a, b)).toBe(true);
  });

  it('matches error parts by message and code', () => {
    const a: MessagePart = { type: 'error', message: 'Oops', code: 'E1' };
    const b: MessagePart = { type: 'error', message: 'Oops', code: 'E1' };
    expect(partsMatch(a, b)).toBe(true);
  });
});

// ------------------------------------------------------------------
// findMatchingPartIndex
// ------------------------------------------------------------------

describe('findMatchingPartIndex', () => {
  it('returns index of matching part', () => {
    const parts: MessagePart[] = [
      { type: 'text', text: 'first' },
      { type: 'text', text: 'second' },
    ];
    const target: MessagePart = { type: 'text', text: 'second' };
    expect(findMatchingPartIndex(parts, target)).toBe(1);
  });

  it('returns -1 when no match', () => {
    const parts: MessagePart[] = [{ type: 'text', text: 'first' }];
    const target: MessagePart = { type: 'text', text: 'nomatch' };
    expect(findMatchingPartIndex(parts, target)).toBe(-1);
  });
});

// ------------------------------------------------------------------
// isOptimisticMessage
// ------------------------------------------------------------------

describe('isOptimisticMessage', () => {
  it('returns true for local-* ids', () => {
    const msg = makeMessage({ id: 'local-1234567890-abc123' });
    expect(isOptimisticMessage(msg)).toBe(true);
  });

  it('returns false for server ids', () => {
    const msg = makeMessage({ id: 'msg-server-1' });
    expect(isOptimisticMessage(msg)).toBe(false);
  });
});

// ------------------------------------------------------------------
// canReconcileOptimistic
// ------------------------------------------------------------------

describe('canReconcileOptimistic', () => {
  const now = new Date();

  it('returns true for matching optimistic and real user messages', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(true);
  });

  it('returns false for non-user roles', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });

  it('returns false for different sessions', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      sessionId: 'sess-a',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      sessionId: 'sess-b',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });

  it('returns false for non-optimistic (server) messages', () => {
    const optimistic = makeMessage({
      id: 'msg-server-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });

  it('returns false when outside time window', () => {
    const oldTime = new Date(now.getTime() - RECONCILE_WINDOW_MS - 1000);
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: oldTime.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });

  it('returns false when text parts differ', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Goodbye' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });

  it('returns false when optimistic has no text part', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'user',
      parts: [{ type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    expect(canReconcileOptimistic(optimistic, real)).toBe(false);
  });
});

// ------------------------------------------------------------------
// sortByCreatedAt
// ------------------------------------------------------------------

describe('sortByCreatedAt', () => {
  it('sorts messages by createdAt ascending', () => {
    const messages: SessionMessage[] = [
      makeMessage({ id: 'm3', createdAt: new Date(3000).toISOString() }),
      makeMessage({ id: 'm1', createdAt: new Date(1000).toISOString() }),
      makeMessage({ id: 'm2', createdAt: new Date(2000).toISOString() }),
    ];
    const sorted = sortByCreatedAt(messages);
    expect(sorted.map((m) => m.id)).toEqual(['m1', 'm2', 'm3']);
  });

  it('preserves original array', () => {
    const messages: SessionMessage[] = [
      makeMessage({ id: 'm2', createdAt: new Date(2000).toISOString() }),
      makeMessage({ id: 'm1', createdAt: new Date(1000).toISOString() }),
    ];
    sortByCreatedAt(messages);
    expect(messages[0].id).toBe('m2');
  });
});

// ------------------------------------------------------------------
// upsertMessageWithReconciliation
// ------------------------------------------------------------------

describe('upsertMessageWithReconciliation', () => {
  const now = new Date();

  it('replaces matching optimistic message with real message', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'user',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([optimistic], real);
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe('msg-real-1');
    expect(result[0].parts[0].type).toBe('text');
    expect((result[0].parts[0] as { text: string }).text).toBe('Hello');
  });

  it('does not duplicate when no optimistic match exists', () => {
    const existing = makeMessage({
      id: 'msg-existing',
      role: 'user',
      parts: [{ type: 'text', text: 'Existing' }],
      createdAt: now.toISOString(),
    });
    const newMsg = makeMessage({
      id: 'msg-new',
      role: 'user',
      parts: [{ type: 'text', text: 'New' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([existing], newMsg);
    expect(result).toHaveLength(2);
    expect(result.map((m) => m.id)).toContain('msg-existing');
    expect(result.map((m) => m.id)).toContain('msg-new');
  });

  it('replaces by id when id already exists', () => {
    const existing = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Old' }],
      createdAt: now.toISOString(),
    });
    const updated = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Updated' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([existing], updated);
    expect(result).toHaveLength(1);
    expect((result[0].parts[0] as { text: string }).text).toBe('Updated');
  });

  it('does not regress assistant text message to empty assistant message', () => {
    const existing = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const incoming = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: '' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([existing], incoming);
    expect(result).toHaveLength(1);
    expect((result[0].parts[0] as { text: string }).text).toBe('Hello');
  });

  it('does not regress assistant text+reasoning to reasoning-only', () => {
    const existing = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [
        { type: 'text', text: '[reasoning] thinking...' },
        { type: 'text', text: 'Hello' },
      ],
      createdAt: now.toISOString(),
    });
    const incoming = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: '[reasoning] thinking...' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([existing], incoming);
    expect(result).toHaveLength(1);
    expect(result[0].parts).toHaveLength(2);
    expect((result[0].parts[1] as { text: string }).text).toBe('Hello');
  });

  it('allows normal replacement when incoming has more displayable parts', () => {
    const existing = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [{ type: 'text', text: '[reasoning] thinking...' }],
      createdAt: now.toISOString(),
    });
    const incoming = makeMessage({
      id: 'msg-1',
      role: 'assistant',
      parts: [
        { type: 'text', text: '[reasoning] thinking...' },
        { type: 'text', text: 'Hello' },
      ],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([existing], incoming);
    expect(result).toHaveLength(1);
    expect(result[0].parts).toHaveLength(2);
    expect((result[0].parts[1] as { text: string }).text).toBe('Hello');
  });

  it('does not reconcile assistant messages', () => {
    const optimistic = makeMessage({
      id: 'local-1234567890-abc',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const real = makeMessage({
      id: 'msg-real-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'Hello' }],
      createdAt: now.toISOString(),
    });
    const result = upsertMessageWithReconciliation([optimistic], real);
    expect(result).toHaveLength(2);
  });

  it('maintains stable ordering by createdAt', () => {
    const messages: SessionMessage[] = [
      makeMessage({ id: 'm1', createdAt: new Date(1000).toISOString() }),
      makeMessage({ id: 'm2', createdAt: new Date(2000).toISOString() }),
    ];
    const newMsg = makeMessage({
      id: 'm0',
      createdAt: new Date(500).toISOString(),
    });
    const result = upsertMessageWithReconciliation(messages, newMsg);
    expect(result.map((m) => m.id)).toEqual(['m0', 'm1', 'm2']);
  });
});

// ------------------------------------------------------------------
// upsertPartWithDedup
// ------------------------------------------------------------------

describe('upsertPartWithDedup', () => {
  it('appends new part when no match', () => {
    const parts: MessagePart[] = [{ type: 'text', text: 'first' }];
    const newPart: MessagePart = { type: 'text', text: 'second' };
    const result = upsertPartWithDedup(parts, newPart);
    expect(result).toHaveLength(2);
    expect((result[1] as { text: string }).text).toBe('second');
  });

  it('replaces matching part instead of duplicating', () => {
    const parts: MessagePart[] = [{ type: 'text', text: 'same' }];
    const updatedPart: MessagePart = { type: 'text', text: 'same' };
    const result = upsertPartWithDedup(parts, updatedPart);
    expect(result).toHaveLength(1);
    expect((result[0] as { text: string }).text).toBe('same');
  });

  it('appends part with different text content', () => {
    const parts: MessagePart[] = [{ type: 'text', text: 'first' }];
    const newPart: MessagePart = { type: 'text', text: 'second' };
    const result = upsertPartWithDedup(parts, newPart);
    expect(result).toHaveLength(2);
    expect((result[1] as { text: string }).text).toBe('second');
  });

  it('does not duplicate tool_call parts with same callId', () => {
    const parts: MessagePart[] = [
      { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' },
    ];
    const updatedPart: MessagePart = {
      type: 'tool_call',
      toolName: 'bash',
      args: { command: 'ls' },
      callId: 'call-1',
    };
    const result = upsertPartWithDedup(parts, updatedPart);
    expect(result).toHaveLength(1);
    expect((result[0] as { args: Record<string, unknown> }).args).toEqual({
      command: 'ls',
    });
  });

  it('appends tool_call parts with different callId', () => {
    const parts: MessagePart[] = [
      { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' },
    ];
    const newPart: MessagePart = {
      type: 'tool_call',
      toolName: 'bash',
      args: {},
      callId: 'call-2',
    };
    const result = upsertPartWithDedup(parts, newPart);
    expect(result).toHaveLength(2);
  });
});

// ------------------------------------------------------------------
// applyTextDeltaToParts
// ------------------------------------------------------------------

describe('applyTextDeltaToParts', () => {
  it('appends delta to the last text part', () => {
    const parts: MessagePart[] = [
      { type: 'text', text: 'Hello ' },
      { type: 'text', text: 'world' },
    ];
    const result = applyTextDeltaToParts(parts, '!');
    expect(result).toHaveLength(2);
    expect((result[1] as { text: string }).text).toBe('world!');
  });

  it('creates a new text part when no text part exists', () => {
    const parts: MessagePart[] = [
      { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' },
    ];
    const result = applyTextDeltaToParts(parts, 'result text');
    expect(result).toHaveLength(2);
    expect((result[1] as { text: string }).text).toBe('result text');
  });

  it('appends to a single text part', () => {
    const parts: MessagePart[] = [{ type: 'text', text: '' }];
    const result = applyTextDeltaToParts(parts, 'Hello');
    expect(result).toHaveLength(1);
    expect((result[0] as { text: string }).text).toBe('Hello');
  });

  it('appends to the only text part among mixed parts', () => {
    const parts: MessagePart[] = [
      { type: 'tool_call', toolName: 'bash', args: {}, callId: 'call-1' },
      { type: 'text', text: '[reasoning] ' },
    ];
    const result = applyTextDeltaToParts(parts, 'thinking...');
    expect(result).toHaveLength(2);
    expect((result[1] as { text: string }).text).toBe('[reasoning] thinking...');
  });
});
