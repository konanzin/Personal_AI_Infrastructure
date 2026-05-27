import type {
  NotificationPayload,
  NotificationType,
  NotificationPriority,
  DeviceRegistration,
  DeviceRegistrationRequest,
  SessionSummary,
  Session,
  SessionStatus,
  SessionMetadata,
  SessionMessage,
  MessagePart,
  TextPart,
  CodePart,
  ToolCallPart,
  ToolResultPart,
  PermissionRequestPart,
  QuestionPart,
  ErrorPart,
  PermissionRequest,
  PermissionResponse,
  PermissionAction,
  RecoveryPayload,
  ConnectionState,
} from '@pai/shared-types';
import type { SchemaResult } from './result';
import {
  isString,
  isNumber,
  isObject,
  isArray,
  isOptional,
  isLiteral,
} from './primitives';

function fail(errors: string | string[]): SchemaResult<never> {
  return { success: false, errors: Array.isArray(errors) ? errors : [errors] };
}

function success<T>(data: T): SchemaResult<T> {
  return { success: true, data };
}

// ------------------------------------------------------------------
// Notification
// ------------------------------------------------------------------

export function validateNotificationPayload(
  value: unknown
): SchemaResult<NotificationPayload> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (
    !isLiteral<NotificationType>(
      'session_complete',
      'session_error',
      'permission_needed',
      'question_asked',
      'scheduled_reminder'
    )(value.type)
  ) {
    errors.push('type must be a valid NotificationType');
  }
  if (!isOptional(isString)(value.sessionId))
    errors.push('sessionId must be a string or undefined');
  if (!isOptional(isString)(value.requestId))
    errors.push('requestId must be a string or undefined');
  if (!isString(value.title)) errors.push('title must be a string');
  if (!isString(value.body)) errors.push('body must be a string');
  if (!isString(value.deepLink)) errors.push('deepLink must be a string');
  if (!isString(value.dedupeKey)) errors.push('dedupeKey must be a string');
  if (!isString(value.timestamp)) errors.push('timestamp must be a string');
  if (!isLiteral<NotificationPriority>('high', 'medium', 'low')(value.priority))
    errors.push('priority must be high, medium, or low');
  if (errors.length > 0) return fail(errors);
  return success(value as NotificationPayload);
}

// ------------------------------------------------------------------
// Device registration
// ------------------------------------------------------------------

export function validateDeviceRegistration(
  value: unknown
): SchemaResult<DeviceRegistration> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.deviceId)) errors.push('deviceId must be a string');
  if (!isLiteral('ios', 'android')(value.platform))
    errors.push('platform must be ios or android');
  if (!isString(value.pushToken)) errors.push('pushToken must be a string');
  if (!isString(value.updatedAt)) errors.push('updatedAt must be a string');
  if (errors.length > 0) return fail(errors);
  return success(value as DeviceRegistration);
}

export function validateDeviceRegistrationRequest(
  value: unknown
): SchemaResult<DeviceRegistrationRequest> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.deviceId)) errors.push('deviceId must be a string');
  if (!isLiteral('ios', 'android')(value.platform))
    errors.push('platform must be ios or android');
  if (!isString(value.pushToken)) errors.push('pushToken must be a string');
  if (!isOptional(isString)(value.appVersion))
    errors.push('appVersion must be a string or undefined');
  if (!isOptional(isString)(value.osVersion))
    errors.push('osVersion must be a string or undefined');
  if (errors.length > 0) return fail(errors);
  return success(value as DeviceRegistrationRequest);
}

// ------------------------------------------------------------------
// Session
// ------------------------------------------------------------------

export function isSessionMetadata(v: unknown): v is SessionMetadata {
  if (!isObject(v)) return false;
  if (v.source !== undefined && !isString(v.source)) return false;
  if (v.tags !== undefined && !isArray(v.tags, isString)) return false;
  return true;
}

export function validateSessionSummary(
  value: unknown
): SchemaResult<SessionSummary> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.id)) errors.push('id must be a string');
  if (!isString(value.title)) errors.push('title must be a string');
  if (!isString(value.updatedAt)) errors.push('updatedAt must be a string');
  if (!isOptional(isString)(value.lastMessagePreview))
    errors.push('lastMessagePreview must be a string or undefined');
  if (!isOptional(isNumber)(value.messageCount))
    errors.push('messageCount must be a number or undefined');
  if (errors.length > 0) return fail(errors);
  return success(value as SessionSummary);
}

export function validateSession(value: unknown): SchemaResult<Session> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.id)) errors.push('id must be a string');
  if (!isString(value.title)) errors.push('title must be a string');
  if (!isLiteral<SessionStatus>('active', 'completed', 'error')(value.status))
    errors.push('status must be active, completed, or error');
  if (!isString(value.createdAt)) errors.push('createdAt must be a string');
  if (!isString(value.updatedAt)) errors.push('updatedAt must be a string');
  if (value.metadata !== undefined && !isSessionMetadata(value.metadata))
    errors.push('metadata must be a valid SessionMetadata object or undefined');
  if (errors.length > 0) return fail(errors);
  return success(value as Session);
}

// ------------------------------------------------------------------
// Message parts
// ------------------------------------------------------------------

export function validateMessagePart(value: unknown): SchemaResult<MessagePart> {
  if (!isObject(value)) return fail('Expected object');
  if (!isString(value.type)) return fail('type must be a string');

  switch (value.type) {
    case 'text': {
      if (!isString(value.text)) return fail('text.text must be a string');
      return success(value as TextPart);
    }
    case 'code': {
      if (!isString(value.language))
        return fail('code.language must be a string');
      if (!isString(value.code)) return fail('code.code must be a string');
      return success(value as CodePart);
    }
    case 'tool_call': {
      if (!isString(value.toolName))
        return fail('tool_call.toolName must be a string');
      if (!isObject(value.args))
        return fail('tool_call.args must be an object');
      if (!isString(value.callId))
        return fail('tool_call.callId must be a string');
      return success(value as ToolCallPart);
    }
    case 'tool_result': {
      if (!isString(value.callId))
        return fail('tool_result.callId must be a string');
      if (!('result' in value))
        return fail('tool_result.result is required');
      if (!isOptional(isString)(value.error))
        return fail('tool_result.error must be a string or undefined');
      return success(value as ToolResultPart);
    }
    case 'permission_request': {
      if (!isString(value.requestId))
        return fail('permission_request.requestId must be a string');
      if (!isString(value.action))
        return fail('permission_request.action must be a string');
      if (!isString(value.resource))
        return fail('permission_request.resource must be a string');
      if (!isString(value.description))
        return fail('permission_request.description must be a string');
      return success(value as PermissionRequestPart);
    }
    case 'question': {
      if (!isString(value.questionId))
        return fail('question.questionId must be a string');
      if (!isString(value.text)) return fail('question.text must be a string');
      if (value.options !== undefined && !isArray(value.options, isString))
        return fail('question.options must be a string array or undefined');
      return success(value as QuestionPart);
    }
    case 'error': {
      if (!isString(value.message))
        return fail('error.message must be a string');
      if (!isOptional(isString)(value.code))
        return fail('error.code must be a string or undefined');
      return success(value as ErrorPart);
    }
    default:
      return fail(`Unknown MessagePart type: ${value.type}`);
  }
}

export function isMessagePart(v: unknown): v is MessagePart {
  return validateMessagePart(v).success;
}

// ------------------------------------------------------------------
// Session message
// ------------------------------------------------------------------

export function isSessionMessage(v: unknown): v is SessionMessage {
  return validateSessionMessage(v).success;
}

export function validateSessionMessage(
  value: unknown
): SchemaResult<SessionMessage> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.id)) errors.push('id must be a string');
  if (!isString(value.sessionId)) errors.push('sessionId must be a string');
  if (!isLiteral('user', 'assistant', 'system')(value.role))
    errors.push('role must be user, assistant, or system');
  if (!isArray(value.parts, isMessagePart))
    errors.push('parts must be an array of MessagePart');
  if (!isString(value.createdAt)) errors.push('createdAt must be a string');
  if (errors.length > 0) return fail(errors);
  return success(value as SessionMessage);
}

// ------------------------------------------------------------------
// Permission
// ------------------------------------------------------------------

export function validatePermissionRequest(
  value: unknown
): SchemaResult<PermissionRequest> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.requestId)) errors.push('requestId must be a string');
  if (!isString(value.action)) errors.push('action must be a string');
  if (!isString(value.resource)) errors.push('resource must be a string');
  if (!isString(value.description))
    errors.push('description must be a string');
  if (!isOptional(isString)(value.sessionId))
    errors.push('sessionId must be a string or undefined');
  if (!isOptional(isString)(value.createdAt))
    errors.push('createdAt must be a string or undefined');
  if (errors.length > 0) return fail(errors);
  return success(value as PermissionRequest);
}

export function validatePermissionResponse(
  value: unknown
): SchemaResult<PermissionResponse> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.requestId)) errors.push('requestId must be a string');
  if (!isLiteral<PermissionAction>('approve', 'deny', 'defer')(value.action))
    errors.push('action must be approve, deny, or defer');
  if (!isString(value.respondedAt))
    errors.push('respondedAt must be a string');
  if (errors.length > 0) return fail(errors);
  return success(value as PermissionResponse);
}

// ------------------------------------------------------------------
// Recovery
// ------------------------------------------------------------------

export function validateRecoveryPayload(
  value: unknown
): SchemaResult<RecoveryPayload> {
  if (!isObject(value)) return fail('Expected object');
  const errors: string[] = [];
  if (!isString(value.sessionId)) errors.push('sessionId must be a string');
  if (!isArray(value.messages, isSessionMessage))
    errors.push('messages must be an array of SessionMessage');
  if (!isOptional(isString)(value.lastEventId))
    errors.push('lastEventId must be a string or undefined');
  if (errors.length > 0) return fail(errors);
  return success(value as RecoveryPayload);
}

// ------------------------------------------------------------------
// Connection state
// ------------------------------------------------------------------

export function validateConnectionState(
  value: unknown
): SchemaResult<ConnectionState> {
  if (
    isLiteral<ConnectionState>(
      'offline',
      'connecting',
      'connected',
      'streaming',
      'stale',
      'reconnecting',
      'authFailed'
    )(value)
  ) {
    return success(value as ConnectionState);
  }
  return fail('Invalid ConnectionState');
}
