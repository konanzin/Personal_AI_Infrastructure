import { describe, it, expect } from 'bun:test';
import {
  validateNotificationPayload,
  validateDeviceRegistration,
  validateDeviceRegistrationRequest,
  validateSessionSummary,
  validateSession,
  validateMessagePart,
  isMessagePart,
  validateSessionMessage,
  isSessionMessage,
  isSessionMetadata,
  validatePermissionRequest,
  validatePermissionResponse,
  validateRecoveryPayload,
  validateConnectionState,
} from './schemas';

// ------------------------------------------------------------------
// Notification
// ------------------------------------------------------------------

describe('validateNotificationPayload', () => {
  it('accepts a valid notification', () => {
    const result = validateNotificationPayload({
      type: 'session_complete',
      sessionId: 's-1',
      title: 'Title',
      body: 'Body',
      deepLink: 'pai://s-1',
      dedupeKey: 's-1:complete',
      timestamp: '2024-01-01T00:00:00Z',
      priority: 'high',
    });
    expect(result.success).toBe(true);
  });

  it('accepts optional fields omitted', () => {
    const result = validateNotificationPayload({
      type: 'scheduled_reminder',
      title: 'Reminder',
      body: 'Do something',
      deepLink: 'pai://reminder',
      dedupeKey: 'rem:1',
      timestamp: '2024-01-01T00:00:00Z',
      priority: 'low',
    });
    expect(result.success).toBe(true);
  });

  it('rejects non-object', () => {
    const result = validateNotificationPayload('bad');
    expect(result.success).toBe(false);
    if (!result.success) expect(result.errors[0]).toBe('Expected object');
  });

  it('rejects invalid type literal', () => {
    const result = validateNotificationPayload({
      type: 'unknown_type',
      title: 'Title',
      body: 'Body',
      deepLink: 'pai://test',
      dedupeKey: 'test',
      timestamp: '2024-01-01T00:00:00Z',
      priority: 'medium',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing required string fields', () => {
    const result = validateNotificationPayload({
      type: 'session_complete',
      title: 123,
      body: null,
      deepLink: '',
      dedupeKey: '',
      timestamp: '',
      priority: 'high',
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
    if (!result.success) {
      expect(result.errors.length).toBeGreaterThan(0);
    }
  });

  it('rejects invalid priority', () => {
    const result = validateNotificationPayload({
      type: 'session_complete',
      title: 'Title',
      body: 'Body',
      deepLink: 'pai://test',
      dedupeKey: 'test',
      timestamp: '2024-01-01T00:00:00Z',
      priority: 'urgent',
    });
    expect(result.success).toBe(false);
  });
});

// ------------------------------------------------------------------
// Device registration
// ------------------------------------------------------------------

describe('validateDeviceRegistration', () => {
  it('accepts a valid registration', () => {
    const result = validateDeviceRegistration({
      deviceId: 'd-1',
      platform: 'ios',
      pushToken: 'tok-1',
      updatedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('accepts android', () => {
    const result = validateDeviceRegistration({
      deviceId: 'd-1',
      platform: 'android',
      pushToken: 'tok-1',
      updatedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('rejects non-object', () => {
    const result = validateDeviceRegistration(null);
    expect(result.success).toBe(false);
  });

  it('rejects invalid platform', () => {
    const result = validateDeviceRegistration({
      deviceId: 'd-1',
      platform: 'web',
      pushToken: 'tok-1',
      updatedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing fields', () => {
    const result = validateDeviceRegistration({
      deviceId: 'd-1',
      platform: 'ios',
    });
    expect(result.success).toBe(false);
  });
});

describe('validateDeviceRegistrationRequest', () => {
  it('accepts a valid request', () => {
    const result = validateDeviceRegistrationRequest({
      deviceId: 'd-1',
      platform: 'ios',
      pushToken: 'tok-1',
    });
    expect(result.success).toBe(true);
  });

  it('accepts optional appVersion and osVersion', () => {
    const result = validateDeviceRegistrationRequest({
      deviceId: 'd-1',
      platform: 'android',
      pushToken: 'tok-1',
      appVersion: '1.0.0',
      osVersion: '14',
    });
    expect(result.success).toBe(true);
  });

  it('rejects invalid optional fields', () => {
    const result = validateDeviceRegistrationRequest({
      deviceId: 'd-1',
      platform: 'ios',
      pushToken: 'tok-1',
      appVersion: 123,
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });
});

// ------------------------------------------------------------------
// Session
// ------------------------------------------------------------------

describe('isSessionMetadata', () => {
  it('accepts valid metadata', () => {
    expect(isSessionMetadata({ source: 'mobile', tags: ['a', 'b'] })).toBe(true);
  });

  it('accepts empty object', () => {
    expect(isSessionMetadata({})).toBe(true);
  });

  it('accepts undefined fields', () => {
    expect(isSessionMetadata({ source: undefined })).toBe(true);
  });

  it('rejects non-object', () => {
    expect(isSessionMetadata(null)).toBe(false);
  });

  it('rejects invalid source type', () => {
    expect(isSessionMetadata({ source: 123 })).toBe(false);
  });

  it('rejects invalid tags type', () => {
    expect(isSessionMetadata({ tags: 'not-array' })).toBe(false);
  });

  it('rejects tags with non-string elements', () => {
    expect(isSessionMetadata({ tags: [1, 2] })).toBe(false);
  });
});

describe('validateSessionSummary', () => {
  it('accepts a valid summary', () => {
    const result = validateSessionSummary({
      id: 's-1',
      title: 'Test',
      updatedAt: '2024-01-01T00:00:00Z',
      messageCount: 5,
    });
    expect(result.success).toBe(true);
  });

  it('accepts optional lastMessagePreview', () => {
    const result = validateSessionSummary({
      id: 's-1',
      title: 'Test',
      updatedAt: '2024-01-01T00:00:00Z',
      lastMessagePreview: 'Hello',
      messageCount: 0,
    });
    expect(result.success).toBe(true);
  });

  it('rejects non-numeric messageCount', () => {
    const result = validateSessionSummary({
      id: 's-1',
      title: 'Test',
      updatedAt: '2024-01-01T00:00:00Z',
      messageCount: 'five',
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects missing required fields', () => {
    const result = validateSessionSummary({ id: 's-1' });
    expect(result.success).toBe(false);
  });
});

describe('validateSession', () => {
  it('accepts a valid session', () => {
    const result = validateSession({
      id: 's-1',
      title: 'Test',
      status: 'active',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('accepts valid metadata', () => {
    const result = validateSession({
      id: 's-1',
      title: 'Test',
      status: 'completed',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
      metadata: { source: 'mobile', tags: ['tag1'] },
    });
    expect(result.success).toBe(true);
  });

  it('rejects invalid status', () => {
    const result = validateSession({
      id: 's-1',
      title: 'Test',
      status: 'deleted',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(false);
  });

  it('rejects invalid metadata', () => {
    const result = validateSession({
      id: 's-1',
      title: 'Test',
      status: 'active',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
      metadata: { tags: [1, 2] },
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });
});

// ------------------------------------------------------------------
// Message parts
// ------------------------------------------------------------------

describe('validateMessagePart', () => {
  it('accepts text part', () => {
    const result = validateMessagePart({ type: 'text', text: 'Hello' });
    expect(result.success).toBe(true);
  });

  it('accepts code part', () => {
    const result = validateMessagePart({ type: 'code', language: 'ts', code: 'const x = 1;' });
    expect(result.success).toBe(true);
  });

  it('accepts tool_call part', () => {
    const result = validateMessagePart({ type: 'tool_call', toolName: 't', args: {}, callId: 'c' });
    expect(result.success).toBe(true);
  });

  it('accepts tool_result part', () => {
    const result = validateMessagePart({ type: 'tool_result', callId: 'c', result: null });
    expect(result.success).toBe(true);
  });

  it('accepts permission_request part', () => {
    const result = validateMessagePart({
      type: 'permission_request',
      requestId: 'r',
      action: 'read',
      resource: 'file',
      description: 'desc',
    });
    expect(result.success).toBe(true);
  });

  it('accepts question part', () => {
    const result = validateMessagePart({ type: 'question', questionId: 'q', text: '?' });
    expect(result.success).toBe(true);
  });

  it('accepts question part with options', () => {
    const result = validateMessagePart({
      type: 'question',
      questionId: 'q',
      text: '?',
      options: ['a', 'b'],
    });
    expect(result.success).toBe(true);
  });

  it('accepts error part', () => {
    const result = validateMessagePart({ type: 'error', message: 'oops' });
    expect(result.success).toBe(true);
  });

  it('rejects non-object', () => {
    const result = validateMessagePart('text');
    expect(result.success).toBe(false);
  });

  it('rejects unknown type', () => {
    const result = validateMessagePart({ type: 'unknown', data: 1 });
    expect(result.success).toBe(false);
  });

  it('rejects text part without text field', () => {
    const result = validateMessagePart({ type: 'text' });
    expect(result.success).toBe(false);
  });

  it('rejects code part with non-string language', () => {
    const result = validateMessagePart({ type: 'code', language: 123, code: 'x' } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects tool_call with non-object args', () => {
    const result = validateMessagePart({ type: 'tool_call', toolName: 't', args: 'bad', callId: 'c' } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects tool_result without result field', () => {
    const result = validateMessagePart({ type: 'tool_result', callId: 'c' });
    expect(result.success).toBe(false);
  });

  it('rejects question with non-string options', () => {
    const result = validateMessagePart({
      type: 'question',
      questionId: 'q',
      text: '?',
      options: [1, 2],
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects error with non-string code', () => {
    const result = validateMessagePart({ type: 'error', message: 'oops', code: 500 } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });
});

describe('isMessagePart', () => {
  it('returns true for valid part', () => {
    expect(isMessagePart({ type: 'text', text: 'hi' })).toBe(true);
  });

  it('returns false for invalid part', () => {
    expect(isMessagePart({ type: 'text' })).toBe(false);
  });
});

// ------------------------------------------------------------------
// Session message
// ------------------------------------------------------------------

describe('validateSessionMessage', () => {
  it('accepts a valid message', () => {
    const result = validateSessionMessage({
      id: 'm-1',
      sessionId: 's-1',
      role: 'user',
      parts: [{ type: 'text', text: 'hi' }],
      createdAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('rejects invalid role', () => {
    const result = validateSessionMessage({
      id: 'm-1',
      sessionId: 's-1',
      role: 'bot',
      parts: [{ type: 'text', text: 'hi' }],
      createdAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(false);
  });

  it('rejects non-array parts', () => {
    const result = validateSessionMessage({
      id: 'm-1',
      sessionId: 's-1',
      role: 'user',
      parts: 'not-array',
      createdAt: '2024-01-01T00:00:00Z',
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects parts containing invalid MessagePart', () => {
    const result = validateSessionMessage({
      id: 'm-1',
      sessionId: 's-1',
      role: 'user',
      parts: [{ type: 'text' }],
      createdAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(false);
  });
});

describe('isSessionMessage', () => {
  it('returns true for valid message', () => {
    expect(isSessionMessage({
      id: 'm-1',
      sessionId: 's-1',
      role: 'assistant',
      parts: [{ type: 'text', text: 'hi' }],
      createdAt: '2024-01-01T00:00:00Z',
    })).toBe(true);
  });

  it('returns false for invalid message', () => {
    expect(isSessionMessage({ id: 'm-1' })).toBe(false);
  });
});

// ------------------------------------------------------------------
// Permission
// ------------------------------------------------------------------

describe('validatePermissionRequest', () => {
  it('accepts a valid request', () => {
    const result = validatePermissionRequest({
      requestId: 'r-1',
      action: 'read',
      resource: 'file',
      description: 'desc',
    });
    expect(result.success).toBe(true);
  });

  it('accepts optional fields', () => {
    const result = validatePermissionRequest({
      requestId: 'r-1',
      action: 'write',
      resource: 'db',
      description: 'desc',
      sessionId: 's-1',
      createdAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('rejects missing required fields', () => {
    const result = validatePermissionRequest({ requestId: 'r-1' });
    expect(result.success).toBe(false);
  });

  it('rejects invalid optional type', () => {
    const result = validatePermissionRequest({
      requestId: 'r-1',
      action: 'read',
      resource: 'file',
      description: 'desc',
      sessionId: 123,
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });
});

describe('validatePermissionResponse', () => {
  it('accepts a valid response', () => {
    const result = validatePermissionResponse({
      requestId: 'r-1',
      action: 'approve',
      respondedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(true);
  });

  it('accepts deny and defer', () => {
    expect(validatePermissionResponse({ requestId: 'r-1', action: 'deny', respondedAt: 't' }).success).toBe(true);
    expect(validatePermissionResponse({ requestId: 'r-1', action: 'defer', respondedAt: 't' }).success).toBe(true);
  });

  it('rejects invalid action', () => {
    const result = validatePermissionResponse({
      requestId: 'r-1',
      action: 'ignore',
      respondedAt: '2024-01-01T00:00:00Z',
    });
    expect(result.success).toBe(false);
  });

  it('rejects missing fields', () => {
    const result = validatePermissionResponse({ requestId: 'r-1' });
    expect(result.success).toBe(false);
  });
});

// ------------------------------------------------------------------
// Recovery
// ------------------------------------------------------------------

describe('validateRecoveryPayload', () => {
  it('accepts a valid payload', () => {
    const result = validateRecoveryPayload({
      sessionId: 's-1',
      messages: [
        {
          id: 'm-1',
          sessionId: 's-1',
          role: 'user',
          parts: [{ type: 'text', text: 'hi' }],
          createdAt: '2024-01-01T00:00:00Z',
        },
      ],
    });
    expect(result.success).toBe(true);
  });

  it('accepts optional lastEventId', () => {
    const result = validateRecoveryPayload({
      sessionId: 's-1',
      messages: [],
      lastEventId: 'evt-1',
    });
    expect(result.success).toBe(true);
  });

  it('rejects non-array messages', () => {
    const result = validateRecoveryPayload({
      sessionId: 's-1',
      messages: 'bad',
    } as unknown as Record<string, unknown>);
    expect(result.success).toBe(false);
  });

  it('rejects invalid message inside array', () => {
    const result = validateRecoveryPayload({
      sessionId: 's-1',
      messages: [{ id: 'm-1' }],
    });
    expect(result.success).toBe(false);
  });
});

// ------------------------------------------------------------------
// Connection state
// ------------------------------------------------------------------

describe('validateConnectionState', () => {
  const validStates = ['offline', 'connecting', 'connected', 'streaming', 'stale', 'reconnecting', 'authFailed'] as const;

  for (const state of validStates) {
    it(`accepts ${state}`, () => {
      const result = validateConnectionState(state);
      expect(result.success).toBe(true);
    });
  }

  it('rejects invalid state', () => {
    const result = validateConnectionState('unknown');
    expect(result.success).toBe(false);
  });

  it('rejects non-string', () => {
    const result = validateConnectionState(42);
    expect(result.success).toBe(false);
  });
});
