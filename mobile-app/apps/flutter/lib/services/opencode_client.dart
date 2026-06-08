import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_event.dart';

/// Configuration for the OpenCode client.
class ClientConfig {
  final String baseUrl;
  final String username;
  final String password;

  ClientConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
  });
}

/// Unified API client for the OpenCode Server.
///
/// Uses Dart's native HTTP streaming to consume SSE events.
/// No polyfills needed — Dart's Stream and http package handle
/// streaming natively.
class OpenCodeClient {
  static const _messageResponseTimeout = Duration(minutes: 5);

  final ClientConfig config;
  http.Client? _httpClient;
  StreamSubscription? _sseSubscription;

  OpenCodeClient(this.config);

  /// Encode Basic Auth header.
  String _encodeBasicAuth() {
    final credentials =
        base64Encode(utf8.encode('${config.username}:${config.password}'));
    return 'Basic $credentials';
  }

  /// Verify credentials by hitting the health endpoint.
  Future<bool> verifyAuth() async {
    final url = Uri.parse('${config.baseUrl}/global/health');

    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': _encodeBasicAuth(),
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Connection timeout - server unreachable');
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Subscribe to the OpenCode event stream.
  ///
  /// Returns a Stream of typed ChatEvent that can be listened to.
  /// The stream emits specific subclasses for each event type.
  ///
  /// Call [unsubscribe] to close the stream.
  Stream<ChatEvent> subscribeToEvents() {
    final url = Uri.parse('${config.baseUrl}/event');

    // Use a persistent client for the SSE connection
    _httpClient = http.Client();

    final request = http.Request('GET', url);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Authorization'] = _encodeBasicAuth();
    request.headers['Cache-Control'] = 'no-cache';

    // Send the request and get the streamed response
    final responseFuture = _httpClient!.send(request);

    final controller = StreamController<ChatEvent>();

    responseFuture.then((response) {
      if (response.statusCode != 200) {
        controller.addError(
          Exception('HTTP ${response.statusCode}: ${response.reasonPhrase}'),
        );
        controller.close();
        return;
      }

      // Emit connected event immediately
      controller.add(const ConnectedEvent());

      // Parse the SSE stream line by line
      var currentEventType = '';
      var currentData = StringBuffer();

      final utf8Decoder = utf8.decoder;
      const lineSplitter = LineSplitter();

      _sseSubscription =
          response.stream.transform(utf8Decoder).transform(lineSplitter).listen(
        (line) {
          if (line.startsWith('event: ')) {
            currentEventType = line.substring(7);
          } else if (line.startsWith('data: ')) {
            if (currentData.isNotEmpty) {
              currentData.write('\n');
            }
            currentData.write(line.substring(6));
          } else if (line.isEmpty) {
            // Empty line means dispatch the event
            if (currentData.isNotEmpty) {
              final rawData = currentData.toString();
              debugPrint(
                  '[PAI_SSE_RAW] Event: $currentEventType | Data: ${rawData.substring(0, rawData.length > 200 ? 200 : rawData.length)}...');
              final event = _buildTypedEvent(
                currentEventType,
                rawData,
              );
              if (event != null) {
                controller.add(event);
              }
            }
            currentEventType = '';
            currentData = StringBuffer();
          }
        },
        onError: (error) {
          controller.add(ErrorEvent(
            error: error,
            message: error.toString(),
          ));
        },
        onDone: () {
          controller.add(const DisconnectedEvent());
          controller.close();
        },
      );
    }).catchError((error) {
      controller.add(ErrorEvent(
        error: error,
        message: error.toString(),
      ));
      controller.close();
    });

    return controller.stream;
  }

  /// Close the SSE connection.
  void unsubscribe() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _httpClient?.close();
    _httpClient = null;
  }

  /// Extract session ID from the various nested shapes OpenCode uses.
  String? _extractSessionId(dynamic parsed) {
    if (parsed is! Map<String, dynamic>) return null;

    final props = parsed['properties'] as Map<String, dynamic>?;
    if (props != null) {
      final info = props['info'] as Map<String, dynamic>?;
      if (info != null && info['sessionID'] is String) {
        return info['sessionID'] as String;
      }

      final part = props['part'] as Map<String, dynamic>?;
      if (part != null && part['sessionID'] is String) {
        return part['sessionID'] as String;
      }

      final message = props['message'] as Map<String, dynamic>?;
      if (message != null && message['sessionID'] is String) {
        return message['sessionID'] as String;
      }

      final session = props['session'] as Map<String, dynamic>?;
      if (session != null && session['id'] is String) {
        return session['id'] as String;
      }

      if (props['sessionID'] is String) {
        return props['sessionID'] as String;
      }
    }

    if (parsed['sessionID'] is String) {
      return parsed['sessionID'] as String;
    }
    if (parsed['sessionId'] is String) {
      return parsed['sessionId'] as String;
    }

    return null;
  }

  /// Build a typed ChatEvent from raw SSE event data.
  ChatEvent? _buildTypedEvent(String eventName, String data) {
    if (eventName.isEmpty && data.isEmpty) return null;

    String rawType = eventName;
    Map<String, dynamic>? parsed;

    if (data.isNotEmpty) {
      try {
        parsed = jsonDecode(data) as Map<String, dynamic>;
        if (rawType.isEmpty && parsed['type'] is String) {
          rawType = parsed['type'] as String;
        }
      } catch (_) {
        // Data is not JSON, treat as plain string
      }
    }

    final sessionId = parsed != null ? _extractSessionId(parsed) : null;

    switch (rawType) {
      case 'server.connected':
        return ConnectedEvent(sessionId: sessionId);
      case 'server.disconnected':
        return DisconnectedEvent(sessionId: sessionId);

      case 'session.next.text.delta':
        final delta = _extractDelta(parsed);
        if (delta != null) {
          return TextDeltaEvent(
            delta: delta,
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.text.ended':
        return TextEndedEvent(sessionId: sessionId, originalEvent: rawType);

      case 'session.next.reasoning.delta':
        final delta = _extractDelta(parsed);
        final reasoningId = _extractReasoningId(parsed);
        if (delta != null) {
          return ReasoningDeltaEvent(
            reasoningId: reasoningId ?? '',
            delta: delta,
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.reasoning.ended':
        final text = _extractText(parsed);
        final reasoningId = _extractReasoningId(parsed);
        return ReasoningEndedEvent(
          reasoningId: reasoningId ?? '',
          text: text ?? '',
          sessionId: sessionId,
          originalEvent: rawType,
        );

      case 'session.next.tool.input.started':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallInputStartedEvent(
            callId: props['callID'] as String? ?? '',
            toolName: props['name'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.input.delta':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallInputDeltaEvent(
            callId: props['callID'] as String? ?? '',
            delta: props['delta'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.input.ended':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallInputEndedEvent(
            callId: props['callID'] as String? ?? '',
            text: props['text'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.called':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallCalledEvent(
            callId: props['callID'] as String? ?? '',
            toolName: props['tool'] as String? ?? '',
            input: (props['input'] as Map<String, dynamic>?) ?? {},
            provider: (props['provider'] as Map<String, dynamic>?) ?? {},
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.progress':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallProgressEvent(
            callId: props['callID'] as String? ?? '',
            structured: (props['structured'] as Map<String, dynamic>?) ?? {},
            content: (props['content'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.success':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallSuccessEvent(
            callId: props['callID'] as String? ?? '',
            structured: (props['structured'] as Map<String, dynamic>?) ?? {},
            content: (props['content'] as List<dynamic>?)
                    ?.cast<Map<String, dynamic>>() ??
                [],
            provider: (props['provider'] as Map<String, dynamic>?) ?? {},
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.failed':
        final props = _extractProperties(parsed);
        if (props != null) {
          final error = props['error'] as Map<String, dynamic>?;
          return ToolCallFailedEvent(
            callId: props['callID'] as String? ?? '',
            errorMessage: error?['message'] as String? ?? 'Unknown error',
            provider: (props['provider'] as Map<String, dynamic>?) ?? {},
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.shell.started':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ShellStartedEvent(
            callId: props['callID'] as String? ?? '',
            command: props['command'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.shell.ended':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ShellEndedEvent(
            callId: props['callID'] as String? ?? '',
            output: props['output'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'permission.asked':
        final props = _extractProperties(parsed);
        if (props != null) {
          return PermissionAskedEvent(
            request: PermissionRequest.fromJson(props),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'permission.replied':
        final props = _extractProperties(parsed);
        if (props != null) {
          return PermissionRepliedEvent(
            requestId: props['requestID'] as String? ?? '',
            reply: props['reply'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'question.asked':
        final props = _extractProperties(parsed);
        if (props != null) {
          return QuestionAskedEvent(
            request: QuestionRequest.fromJson(props),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'question.replied':
        final props = _extractProperties(parsed);
        if (props != null) {
          final answers = (props['answers'] as List<dynamic>?)
                  ?.map((a) => (a as List<dynamic>).cast<String>())
                  .toList() ??
              [];
          return QuestionRepliedEvent(
            requestId: props['requestID'] as String? ?? '',
            answers: answers,
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'question.rejected':
        final props = _extractProperties(parsed);
        if (props != null) {
          return QuestionRejectedEvent(
            requestId: props['requestID'] as String? ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'message.updated':
      case 'message.part.updated':
      case 'message.part.delta':
        if (parsed != null) {
          return MessageEvent(
            payload: parsed,
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.status':
      case 'session.idle':
      case 'session.error':
      case 'session.created':
      case 'session.updated':
      case 'session.deleted':
      case 'session.compacted':
      case 'session.diff':
      case 'todo.updated':
      case 'file.edited':
      case 'file.watcher.updated':
      case 'session.next.step.started':
      case 'session.next.step.ended':
      case 'session.next.step.failed':
      case 'session.next.agent.switched':
      case 'session.next.model.switched':
      case 'session.next.compaction.started':
      case 'session.next.compaction.delta':
      case 'session.next.compaction.ended':
        if (parsed != null) {
          return StatusEvent(
            payload: parsed,
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'error':
        return ErrorEvent(
          message: data,
          sessionId: sessionId,
          originalEvent: rawType,
        );
    }

    // Fallback: unknown event type - wrap as generic message/status
    if (parsed != null) {
      if (rawType.startsWith('message.')) {
        return MessageEvent(
          payload: parsed,
          sessionId: sessionId,
          originalEvent: rawType,
        );
      }
      return StatusEvent(
        payload: parsed,
        sessionId: sessionId,
        originalEvent: rawType,
      );
    }

    return null;
  }

  @visibleForTesting
  ChatEvent? buildTypedEventForTest(String eventName, String data) {
    return _buildTypedEvent(eventName, data);
  }

  /// Extract properties map from event payload.
  Map<String, dynamic>? _extractProperties(Map<String, dynamic>? parsed) {
    if (parsed == null) return null;
    final props = parsed['properties'];
    if (props is Map<String, dynamic>) return props;
    if (props is Map) return Map<String, dynamic>.from(props);
    return null;
  }

  /// Extract delta text from event.
  String? _extractDelta(Map<String, dynamic>? parsed) {
    final props = _extractProperties(parsed);
    if (props != null) {
      final delta = props['delta'];
      if (delta is String) return delta;
      if (delta is Map) {
        final text = delta['text'] as String?;
        if (text != null) return text;
      }
    }
    final delta = parsed?['delta'];
    if (delta is String) return delta;
    if (delta is Map) {
      final text = delta['text'] as String?;
      if (text != null) return text;
    }
    return null;
  }

  /// Extract text from event.
  String? _extractText(Map<String, dynamic>? parsed) {
    final props = _extractProperties(parsed);
    if (props != null) {
      final text = props['text'];
      if (text is String) return text;
    }
    final text = parsed?['text'];
    if (text is String) return text;
    return null;
  }

  /// Extract reasoning ID from event.
  String? _extractReasoningId(Map<String, dynamic>? parsed) {
    final props = _extractProperties(parsed);
    if (props != null) {
      final id = props['reasoningID'];
      if (id is String) return id;
    }
    return null;
  }

  /// Create a new session.
  Future<Map<String, dynamic>> createSession({String? title}) async {
    final url = Uri.parse('${config.baseUrl}/session');
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({if (title != null) 'title': title}),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to create session: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Send a message to a session.
  ///
  /// Uses the correct endpoint: POST /session/{sessionID}/message
  /// Body: { "parts": [{"type": "text", "text": "..."}] }
  Future<void> sendMessage(String sessionId, String text) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/message');

    final body = jsonEncode({
      'parts': [
        {'type': 'text', 'text': text}
      ]
    });

    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(_messageResponseTimeout);

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'Failed to send message: ${response.statusCode} - ${response.body}');
    }
  }

  /// List all sessions.
  Future<List<dynamic>> listSessions() async {
    final url = Uri.parse('${config.baseUrl}/session');
    final response = await http.get(
      url,
      headers: {
        'Authorization': _encodeBasicAuth(),
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to list sessions: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is Map && data.containsKey('items')) {
      return data['items'] as List<dynamic>;
    }
    return data as List<dynamic>;
  }

  /// Update session metadata (title, etc).
  Future<void> updateSession(
    String sessionId, {
    String? title,
  }) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId');
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;

    final response = await http
        .patch(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': _encodeBasicAuth(),
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to update session: ${response.statusCode}');
    }
  }

  /// Delete a session.
  Future<void> deleteSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId');
    final response = await http.delete(
      url,
      headers: {
        'Authorization': _encodeBasicAuth(),
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to delete session: ${response.statusCode}');
    }
  }

  /// Fetch messages for a session.
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/message');
    final response = await http.get(
      url,
      headers: {
        'Authorization': _encodeBasicAuth(),
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Failed to get messages: ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    if (data is List) {
      return data;
    }
    return [];
  }

  /// Abort a running session (stop generation).
  Future<void> abortSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/abort');
    await http.post(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
  }

  /// Get session details (model, cost, tokens, etc).
  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId');
    final response = await http.get(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to get session: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// List available providers and models.
  Future<Map<String, dynamic>> getProviders() async {
    final url = Uri.parse('${config.baseUrl}/provider');
    final response = await http.get(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to get providers: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Send a message with optional model/parts override.
  Future<void> sendMessageAdvanced(
    String sessionId, {
    required List<Map<String, dynamic>> parts,
    Map<String, String>? model,
  }) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/message');
    final body = <String, dynamic>{'parts': parts};
    if (model != null) body['model'] = model;
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_messageResponseTimeout);
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to send message: ${response.statusCode}');
    }
  }

  /// Fork a session at a specific message.
  Future<Map<String, dynamic>> forkSession(
      String sessionId, String messageId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/fork');
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'messageID': messageId}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to fork session: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Create or remove a share link for a session.
  Future<Map<String, dynamic>> shareSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/share');
    final response = await http.post(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to share session: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<void> unshareSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/share');
    final response = await http.delete(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to unshare session: ${response.statusCode}');
    }
  }

  /// Revert a message (undo file changes).
  Future<void> revertMessage(String sessionId, String messageId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/revert');
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'messageID': messageId}),
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to revert message: ${response.statusCode}');
    }
  }

  /// Unrevert messages in a session.
  Future<void> unrevertSession(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/unrevert');
    final response = await http.post(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to unrevert: ${response.statusCode}');
    }
  }

  /// Get session todos.
  Future<List<dynamic>> getSessionTodos(String sessionId) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/todo');
    final response = await http.get(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to get todos: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is List) return data;
    return [];
  }

  /// List available slash commands.
  Future<List<dynamic>> getCommands() async {
    final url = Uri.parse('${config.baseUrl}/command');
    final response = await http.get(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('Failed to get commands: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is List) return data;
    return [];
  }

  /// Execute a slash command.
  Future<void> executeCommand(String sessionId, String command,
      {String? arguments}) async {
    final url = Uri.parse('${config.baseUrl}/session/$sessionId/command');
    final body = <String, dynamic>{'command': command};
    if (arguments != null) body['arguments'] = arguments;
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception('Failed to execute command: ${response.statusCode}');
    }
  }

  /// Generic GET request.
  Future<http.Response> get(String path) async {
    final url = Uri.parse('${config.baseUrl}$path');
    final response = await http.get(
      url,
      headers: {'Authorization': _encodeBasicAuth()},
    ).timeout(const Duration(seconds: 10));
    return response;
  }

  /// Generic POST request to an endpoint path.
  Future<http.Response> post(String path, {String? body}) async {
    final url = Uri.parse('${config.baseUrl}$path');
    final response = await http
        .post(
          url,
          headers: {
            'Authorization': _encodeBasicAuth(),
            if (body != null) 'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw Exception(
          'POST $path failed: ${response.statusCode} - ${response.body}');
    }

    return response;
  }
}
