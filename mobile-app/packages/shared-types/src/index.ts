/**
 * Shared TypeScript types for PAI Mobile
 *
 * Contracts shared between the mobile app and the OpenCode notification plugin.
 */

// ------------------------------------------------------------------
// Session types
// ------------------------------------------------------------------

export type SessionStatus = 'active' | 'completed' | 'error';

export type SessionSummary = {
  id: string;
  title: string;
  updatedAt: string;
  lastMessagePreview?: string;
  messageCount?: number;
};

export type Session = {
  id: string;
  title: string;
  status: SessionStatus;
  createdAt: string;
  updatedAt: string;
  metadata?: SessionMetadata;
};

export type SessionMetadata = {
  source?: string;
  tags?: string[];
};

export type SessionMessage = {
  id: string;
  sessionId: string;
  role: 'user' | 'assistant' | 'system';
  parts: MessagePart[];
  createdAt: string;
};

// ------------------------------------------------------------------
// Message part types
// ------------------------------------------------------------------

export type MessagePartType = MessagePart['type'];

export type MessagePart =
  | TextPart
  | CodePart
  | ToolCallPart
  | ToolResultPart
  | PermissionRequestPart
  | QuestionPart
  | ErrorPart;

export type TextPart = {
  type: 'text';
  text: string;
};

export type CodePart = {
  type: 'code';
  language: string;
  code: string;
};

export type ToolCallPart = {
  type: 'tool_call';
  toolName: string;
  args: Record<string, unknown>;
  callId: string;
};

export type ToolResultPart = {
  type: 'tool_result';
  callId: string;
  result: unknown;
  error?: string;
};

export type PermissionRequestPart = {
  type: 'permission_request';
  requestId: string;
  action: string;
  resource: string;
  description: string;
};

export type QuestionPart = {
  type: 'question';
  questionId: string;
  text: string;
  options?: string[];
};

export type ErrorPart = {
  type: 'error';
  message: string;
  code?: string;
};

// ------------------------------------------------------------------
// Notification types
// ------------------------------------------------------------------

export type NotificationType =
  | 'session_complete'
  | 'session_error'
  | 'permission_needed'
  | 'question_asked'
  | 'scheduled_reminder';

export type NotificationPriority = 'high' | 'medium' | 'low';

export type NotificationPayload = {
  type: NotificationType;
  sessionId?: string;
  requestId?: string;
  title: string;
  body: string;
  deepLink: string;
  dedupeKey: string;
  timestamp: string;
  priority: NotificationPriority;
};

// ------------------------------------------------------------------
// Permission types
// ------------------------------------------------------------------

export type PermissionAction = 'approve' | 'deny' | 'defer';

export type PermissionStatus = 'pending' | 'approved' | 'denied' | 'deferred';

export type PermissionRequest = {
  requestId: string;
  action: string;
  resource: string;
  description: string;
  sessionId?: string;
  createdAt?: string;
};

export type PermissionResponse = {
  requestId: string;
  action: PermissionAction;
  respondedAt: string;
};

// ------------------------------------------------------------------
// Device registration
// ------------------------------------------------------------------

export type DeviceRegistration = {
  deviceId: string;
  platform: 'ios' | 'android';
  pushToken: string;
  updatedAt: string;
};

export type DeviceRegistrationRequest = {
  deviceId: string;
  platform: 'ios' | 'android';
  pushToken: string;
  appVersion?: string;
  osVersion?: string;
};

// ------------------------------------------------------------------
// Recovery
// ------------------------------------------------------------------

export type RecoveryPayload = {
  sessionId: string;
  messages: SessionMessage[];
  lastEventId?: string;
};

// ------------------------------------------------------------------
// Connection state
// ------------------------------------------------------------------

export type ConnectionState =
  | 'offline'
  | 'connecting'
  | 'connected'
  | 'streaming'
  | 'stale'
  | 'reconnecting'
  | 'authFailed';
