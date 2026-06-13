/// Base class for all chat events from the OpenCode SSE stream.
String _eventString(dynamic value) {
  if (value == null) return '';
  if (value is String) return value;
  return value.toString();
}

Map<String, dynamic>? _eventMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

Map<String, dynamic> _eventMapOrEmpty(dynamic value) {
  return _eventMap(value) ?? const {};
}

List<String> _eventStringList(dynamic value) {
  if (value is! List) return const [];
  return [for (final item in value) _eventString(item)];
}

List<Map<String, dynamic>> _eventMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

abstract class ChatEvent {
  final String type;
  final String? sessionId;
  final String? originalEvent;

  const ChatEvent({
    required this.type,
    this.sessionId,
    this.originalEvent,
  });

  @override
  String toString() => 'ChatEvent(type: $type, sessionId: $sessionId)';
}

/// Connection established event.
class ConnectedEvent extends ChatEvent {
  const ConnectedEvent({super.sessionId}) : super(type: 'connected');
}

/// Connection closed event.
class DisconnectedEvent extends ChatEvent {
  const DisconnectedEvent({super.sessionId}) : super(type: 'disconnected');
}

/// Generic status event (session.status, session.idle, etc.)
class StatusEvent extends ChatEvent {
  final Map<String, dynamic> payload;

  const StatusEvent({
    required this.payload,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'status');
}

/// Error event.
class ErrorEvent extends ChatEvent {
  final dynamic error;
  final String? message;

  const ErrorEvent({
    this.error,
    this.message,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'error');

  @override
  String toString() => 'ErrorEvent(message: $message)';
}

/// Message-related event: message.updated, message.part.updated, etc.
class MessageEvent extends ChatEvent {
  final Map<String, dynamic> payload;

  const MessageEvent({
    required this.payload,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'message');
}

/// Tool call input started (agent thinking about input).
class ToolCallInputStartedEvent extends ChatEvent {
  final String callId;
  final String toolName;

  const ToolCallInputStartedEvent({
    required this.callId,
    required this.toolName,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_input_started');
}

/// Tool call input delta (streaming input).
class ToolCallInputDeltaEvent extends ChatEvent {
  final String callId;
  final String delta;

  const ToolCallInputDeltaEvent({
    required this.callId,
    required this.delta,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_input_delta');
}

/// Tool call input ended.
class ToolCallInputEndedEvent extends ChatEvent {
  final String callId;
  final String text;

  const ToolCallInputEndedEvent({
    required this.callId,
    required this.text,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_input_ended');
}

/// Tool was called (executed).
class ToolCallCalledEvent extends ChatEvent {
  final String callId;
  final String toolName;
  final Map<String, dynamic> input;
  final Map<String, dynamic> provider;

  const ToolCallCalledEvent({
    required this.callId,
    required this.toolName,
    required this.input,
    required this.provider,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_called');
}

/// Tool progress update.
class ToolCallProgressEvent extends ChatEvent {
  final String callId;
  final Map<String, dynamic> structured;
  final List<Map<String, dynamic>> content;

  const ToolCallProgressEvent({
    required this.callId,
    required this.structured,
    required this.content,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_progress');
}

/// Tool completed successfully.
class ToolCallSuccessEvent extends ChatEvent {
  final String callId;
  final Map<String, dynamic> structured;
  final List<Map<String, dynamic>> content;
  final Map<String, dynamic> provider;

  const ToolCallSuccessEvent({
    required this.callId,
    required this.structured,
    required this.content,
    required this.provider,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_success');
}

/// Tool failed.
class ToolCallFailedEvent extends ChatEvent {
  final String callId;
  final String errorMessage;
  final Map<String, dynamic> provider;

  const ToolCallFailedEvent({
    required this.callId,
    required this.errorMessage,
    required this.provider,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'tool_call_failed');
}

/// Shell command started.
class ShellStartedEvent extends ChatEvent {
  final String callId;
  final String command;

  const ShellStartedEvent({
    required this.callId,
    required this.command,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'shell_started');
}

/// Shell command ended.
class ShellEndedEvent extends ChatEvent {
  final String callId;
  final String output;

  const ShellEndedEvent({
    required this.callId,
    required this.output,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'shell_ended');
}

/// Permission asked by agent.
class PermissionAskedEvent extends ChatEvent {
  final PermissionRequest request;

  const PermissionAskedEvent({
    required this.request,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'permission_asked');
}

/// Permission replied by user (confirmation from server).
class PermissionRepliedEvent extends ChatEvent {
  final String requestId;
  final String reply; // 'once', 'always', 'reject'

  const PermissionRepliedEvent({
    required this.requestId,
    required this.reply,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'permission_replied');
}

/// Question asked by agent.
class QuestionAskedEvent extends ChatEvent {
  final QuestionRequest request;

  const QuestionAskedEvent({
    required this.request,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'question_asked');
}

/// Question replied by user (confirmation from server).
class QuestionRepliedEvent extends ChatEvent {
  final String requestId;
  final List<List<String>> answers;

  const QuestionRepliedEvent({
    required this.requestId,
    required this.answers,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'question_replied');
}

/// Question rejected by user (confirmation from server).
class QuestionRejectedEvent extends ChatEvent {
  final String requestId;

  const QuestionRejectedEvent({
    required this.requestId,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'question_rejected');
}

/// Text delta from assistant response.
class TextDeltaEvent extends ChatEvent {
  final String delta;

  const TextDeltaEvent({
    required this.delta,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'text_delta');
}

/// Text ended.
class TextEndedEvent extends ChatEvent {
  const TextEndedEvent({super.sessionId, super.originalEvent})
      : super(type: 'text_ended');
}

/// Reasoning delta from assistant.
class ReasoningDeltaEvent extends ChatEvent {
  final String reasoningId;
  final String delta;

  const ReasoningDeltaEvent({
    required this.reasoningId,
    required this.delta,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'reasoning_delta');
}

/// Reasoning ended.
class ReasoningEndedEvent extends ChatEvent {
  final String reasoningId;
  final String text;

  const ReasoningEndedEvent({
    required this.reasoningId,
    required this.text,
    super.sessionId,
    super.originalEvent,
  }) : super(type: 'reasoning_ended');
}

/// Resposta possível para uma solicitação de permissão.
enum PermissionReply { once, always, reject }

/// Permission request model.
class PermissionRequest {
  final String id;
  final String sessionID;
  final String permission;
  final List<String> patterns;
  final Map<String, dynamic> metadata;
  final List<String> always;
  final ToolReference? tool;

  const PermissionRequest({
    required this.id,
    required this.sessionID,
    required this.permission,
    required this.patterns,
    required this.metadata,
    required this.always,
    this.tool,
  });

  factory PermissionRequest.fromJson(Map<String, dynamic> json) {
    final toolJson = _eventMap(json['tool']);
    return PermissionRequest(
      id: _eventString(json['id']),
      sessionID: _eventString(json['sessionID']),
      permission: _eventString(json['permission']),
      patterns: _eventStringList(json['patterns']),
      metadata: _eventMapOrEmpty(json['metadata']),
      always: _eventStringList(json['always']),
      tool: toolJson != null ? ToolReference.fromJson(toolJson) : null,
    );
  }
}

/// Tool reference within permission/question.
class ToolReference {
  final String messageID;
  final String callID;

  const ToolReference({
    required this.messageID,
    required this.callID,
  });

  factory ToolReference.fromJson(Map<String, dynamic> json) {
    return ToolReference(
      messageID: _eventString(json['messageID']),
      callID: _eventString(json['callID']),
    );
  }
}

/// Question request model.
class QuestionRequest {
  final String id;
  final String sessionID;
  final List<QuestionInfo> questions;
  final QuestionTool? tool;

  const QuestionRequest({
    required this.id,
    required this.sessionID,
    required this.questions,
    this.tool,
  });

  factory QuestionRequest.fromJson(Map<String, dynamic> json) {
    final toolJson = _eventMap(json['tool']);
    return QuestionRequest(
      id: _eventString(json['id']),
      sessionID: _eventString(json['sessionID']),
      questions:
          _eventMapList(json['questions']).map(QuestionInfo.fromJson).toList(),
      tool: toolJson != null ? QuestionTool.fromJson(toolJson) : null,
    );
  }
}

/// Question info.
class QuestionInfo {
  final String question;
  final String header;
  final List<QuestionOption> options;
  final bool multiple;
  final bool custom;

  const QuestionInfo({
    required this.question,
    required this.header,
    required this.options,
    this.multiple = false,
    this.custom = false,
  });

  factory QuestionInfo.fromJson(Map<String, dynamic> json) {
    return QuestionInfo(
      question: _eventString(json['question']),
      header: _eventString(json['header']),
      options:
          _eventMapList(json['options']).map(QuestionOption.fromJson).toList(),
      multiple: json['multiple'] == true,
      custom: json['custom'] == true,
    );
  }
}

/// Question option.
class QuestionOption {
  final String label;
  final String description;

  const QuestionOption({
    required this.label,
    required this.description,
  });

  factory QuestionOption.fromJson(Map<String, dynamic> json) {
    return QuestionOption(
      label: _eventString(json['label']),
      description: _eventString(json['description']),
    );
  }
}

/// Question tool reference.
class QuestionTool {
  final String messageID;
  final String callID;

  const QuestionTool({
    required this.messageID,
    required this.callID,
  });

  factory QuestionTool.fromJson(Map<String, dynamic> json) {
    return QuestionTool(
      messageID: _eventString(json['messageID']),
      callID: _eventString(json['callID']),
    );
  }
}
