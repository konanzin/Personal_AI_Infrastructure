/// Base class for all message parts in a chat message.
abstract class MessagePart {
  String get type;
}

/// Plain text part.
class TextPart implements MessagePart {
  final String text;
  
  @override
  String get type => 'text';
  
  const TextPart({required this.text});
}

/// Reasoning part (agent's thought process).
class ReasoningPart implements MessagePart {
  final String id;
  final String text;
  
  @override
  String get type => 'reasoning';
  
  const ReasoningPart({required this.id, required this.text});
}

/// Tool call part with state machine.
class ToolCallPart implements MessagePart {
  final String id;
  final String name;
  ToolCallState state;
  final Map<String, dynamic> input;
  List<ToolContent> content;
  String? errorMessage;
  
  @override
  String get type => 'tool';
  
  ToolCallPart({
    required this.id,
    required this.name,
    this.state = ToolCallState.pending,
    this.input = const {},
    this.content = const [],
    this.errorMessage,
  });
}

/// States for a tool call.
enum ToolCallState {
  pending,
  running,
  completed,
  error,
}

/// Shell command part.
class ShellPart implements MessagePart {
  final String callId;
  final String command;
  final String output;
  
  @override
  String get type => 'shell';
  
  const ShellPart({
    required this.callId,
    required this.command,
    required this.output,
  });
}

/// Content returned by a tool call.
abstract class ToolContent {
  String get contentType;
}

/// Text content from tool.
class ToolTextContent implements ToolContent {
  final String text;
  
  @override
  String get contentType => 'text';
  
  const ToolTextContent({required this.text});
  
  factory ToolTextContent.fromJson(Map<String, dynamic> json) {
    return ToolTextContent(text: json['text'] as String? ?? '');
  }
}

/// File content from tool.
class ToolFileContent implements ToolContent {
  final String uri;
  final String mime;
  final String? name;
  
  @override
  String get contentType => 'file';
  
  const ToolFileContent({
    required this.uri,
    required this.mime,
    this.name,
  });
  
  factory ToolFileContent.fromJson(Map<String, dynamic> json) {
    return ToolFileContent(
      uri: json['uri'] as String? ?? '',
      mime: json['mime'] as String? ?? '',
      name: json['name'] as String?,
    );
  }
}

/// Parse a list of tool content from JSON.
List<ToolContent> parseToolContent(List<dynamic> jsonList) {
  return jsonList.map((item) {
    if (item is! Map<String, dynamic>) return ToolTextContent(text: '');
    final type = item['type'] as String?;
    if (type == 'file') {
      return ToolFileContent.fromJson(item);
    }
    return ToolTextContent.fromJson(item);
  }).toList();
}
