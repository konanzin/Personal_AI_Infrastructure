/**
 * Test Utilities
 *
 * Shared mocks, fixtures, and helpers for testing across the monorepo.
 */

import type {
  SessionSummary,
  Session,
  SessionMessage,
  MessagePart,
  NotificationPayload,
  PermissionRequest,
  PermissionResponse,
  DeviceRegistration,
  DeviceRegistrationRequest,
  RecoveryPayload,
  ConnectionState,
} from '@pai/shared-types';

export function createMockSessionSummary(
  overrides?: Partial<SessionSummary>
): SessionSummary {
  return {
    id: 'session-test-001',
    title: 'Test Session',
    updatedAt: new Date().toISOString(),
    messageCount: 0,
    ...overrides,
  };
}

export function createMockFullSession(overrides?: Partial<Session>): Session {
  return {
    id: 'session-test-001',
    title: 'Test Session',
    status: 'active',
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

export function createMockMessage(
  overrides?: Partial<SessionMessage>
): SessionMessage {
  return {
    id: 'msg-test-001',
    sessionId: 'session-test-001',
    role: 'user',
    parts: [{ type: 'text', text: 'Hello PAI' }],
    createdAt: new Date().toISOString(),
    ...overrides,
  };
}

export function createMockTextPart(text = 'Hello PAI'): MessagePart {
  return { type: 'text', text };
}

export function createMockCodePart(
  language = 'typescript',
  code = 'const x = 1;'
): MessagePart {
  return { type: 'code', language, code };
}

export function createMockToolCallPart(
  toolName = 'testTool',
  args: Record<string, unknown> = {},
  callId = 'call-001'
): MessagePart {
  return { type: 'tool_call', toolName, args, callId };
}

export function createMockToolResultPart(
  callId = 'call-001',
  result: unknown = null,
  error?: string
): MessagePart {
  return { type: 'tool_result', callId, result, error };
}

export function createMockPermissionRequestPart(
  requestId = 'perm-001',
  action = 'read',
  resource = 'file',
  description = 'Allow reading?'
): MessagePart {
  return {
    type: 'permission_request',
    requestId,
    action,
    resource,
    description,
  };
}

export function createMockQuestionPart(
  questionId = 'q-001',
  text = 'What is your choice?',
  options?: string[]
): MessagePart {
  return { type: 'question', questionId, text, options };
}

export function createMockErrorPart(
  message = 'Something went wrong',
  code?: string
): MessagePart {
  return { type: 'error', message, code };
}

export function createMockNotification(
  overrides?: Partial<NotificationPayload>
): NotificationPayload {
  return {
    type: 'session_complete',
    sessionId: 'session-test-001',
    title: 'Session Complete',
    body: 'Your session has finished.',
    deepLink: 'pai://session/session-test-001',
    dedupeKey: 'session-test-001:complete',
    timestamp: new Date().toISOString(),
    priority: 'medium',
    ...overrides,
  };
}

export function createMockPermissionRequest(
  overrides?: Partial<PermissionRequest>
): PermissionRequest {
  return {
    requestId: 'perm-test-001',
    action: 'read',
    resource: 'files',
    description: 'Allow reading files?',
    ...overrides,
  };
}

export function createMockPermissionResponse(
  overrides?: Partial<PermissionResponse>
): PermissionResponse {
  return {
    requestId: 'perm-test-001',
    action: 'approve',
    respondedAt: new Date().toISOString(),
    ...overrides,
  };
}

export function createMockDeviceRegistration(
  overrides?: Partial<DeviceRegistration>
): DeviceRegistration {
  return {
    deviceId: 'device-test-001',
    platform: 'ios',
    pushToken: 'ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]',
    updatedAt: new Date().toISOString(),
    ...overrides,
  };
}

export function createMockDeviceRegistrationRequest(
  overrides?: Partial<DeviceRegistrationRequest>
): DeviceRegistrationRequest {
  return {
    deviceId: 'device-test-001',
    platform: 'ios',
    pushToken: 'ExponentPushToken[xxxxxxxxxxxxxxxxxxxxxx]',
    ...overrides,
  };
}

export function createMockRecoveryPayload(
  overrides?: Partial<RecoveryPayload>
): RecoveryPayload {
  return {
    sessionId: 'session-test-001',
    messages: [createMockMessage()],
    ...overrides,
  };
}

export function createMockConnectionState(
  state: ConnectionState = 'connected'
): ConnectionState {
  return state;
}
