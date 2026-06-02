/// Represents an event from the OpenCode SSE stream.
/// 
/// Maps 1:1 with the TypeScript OpenCodeEvent type from the mobile client.
class OpenCodeEvent {
  final String type; // 'connected', 'message', 'status', 'error', 'disconnected'
  final dynamic data;
  final String? sessionId;
  final String? originalEvent;

  OpenCodeEvent({
    required this.type,
    this.data,
    this.sessionId,
    this.originalEvent,
  });

  @override
  String toString() {
    return 'OpenCodeEvent(type: $type, sessionId: $sessionId, originalEvent: $originalEvent)';
  }
}
