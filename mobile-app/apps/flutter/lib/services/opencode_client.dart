import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_event.dart';
import 'api_errors.dart';

/// Configuration for the OpenCode client.
class ClientConfig {
  final String baseUrl;
  final String username;
  final String password;
  final int connectTimeoutSeconds;
  final int requestTimeoutSeconds;
  final int sseHeartbeatSeconds;

  ClientConfig({
    required String baseUrl,
    required this.username,
    required this.password,
    this.connectTimeoutSeconds = 10,
    this.requestTimeoutSeconds = 30,
    this.sseHeartbeatSeconds = 90,
  }) : baseUrl = normalizeBaseUrl(baseUrl);

  Duration get connectTimeout => Duration(seconds: connectTimeoutSeconds);
  Duration get requestTimeout => Duration(seconds: requestTimeoutSeconds);
  Duration get sseHeartbeatTimeout => Duration(seconds: sseHeartbeatSeconds);

  static String normalizeBaseUrl(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return normalized;
    final hasScheme =
        RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(normalized);
    if (!hasScheme) normalized = 'http://$normalized';
    while (normalized.endsWith('/') && !normalized.endsWith('://')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

class ConnectionCheckResult {
  final bool success;
  final String message;
  final ApiError? error;

  const ConnectionCheckResult._({
    required this.success,
    required this.message,
    this.error,
  });

  const ConnectionCheckResult.success()
      : this._(success: true, message: 'Connection successful');

  const ConnectionCheckResult.failure(String message, {ApiError? error})
      : this._(success: false, message: message, error: error);
}

class OpenCodeSession {
  final String id;
  final String? title;
  final String? directory;
  final Map<String, dynamic> raw;

  const OpenCodeSession({
    required this.id,
    this.title,
    this.directory,
    required this.raw,
  });

  factory OpenCodeSession.fromJson(Map<String, dynamic> json) {
    return OpenCodeSession(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString(),
      directory: json['directory']?.toString(),
      raw: json,
    );
  }
}

class OpenCodeMessageRecord {
  final String? id;
  final String? role;
  final List<dynamic> parts;
  final Map<String, dynamic> raw;

  const OpenCodeMessageRecord({
    this.id,
    this.role,
    required this.parts,
    required this.raw,
  });

  factory OpenCodeMessageRecord.fromJson(Map<String, dynamic> json) {
    final info = json['info'] as Map?;
    return OpenCodeMessageRecord(
      id: info?['id']?.toString(),
      role: info?['role']?.toString(),
      parts: json['parts'] is List ? json['parts'] as List<dynamic> : const [],
      raw: json,
    );
  }
}

class OpenCodeTodoItem {
  final String? id;
  final String? title;
  final String? status;
  final Map<String, dynamic> raw;

  const OpenCodeTodoItem({
    this.id,
    this.title,
    this.status,
    required this.raw,
  });

  factory OpenCodeTodoItem.fromJson(Map<String, dynamic> json) {
    return OpenCodeTodoItem(
      id: json['id']?.toString(),
      title: (json['title'] ?? json['text'] ?? json['content'])?.toString(),
      status: json['status']?.toString(),
      raw: json,
    );
  }
}

class OpenCodeCommandItem {
  final String name;
  final String? description;
  final Map<String, dynamic> raw;

  const OpenCodeCommandItem({
    required this.name,
    this.description,
    required this.raw,
  });

  factory OpenCodeCommandItem.fromJson(Map<String, dynamic> json) {
    return OpenCodeCommandItem(
      name: (json['name'] ?? json['command'] ?? '').toString(),
      description: json['description']?.toString(),
      raw: json,
    );
  }
}

class OpenCodeFileMatch {
  final String path;

  const OpenCodeFileMatch(this.path);
}

class OpenCodeProviderRegistry {
  final Map<String, dynamic> raw;

  const OpenCodeProviderRegistry(this.raw);

  Iterable<String> get providerIds => raw.keys;
}

/// Unified API client for the OpenCode Server.
///
/// Uses Dart's native HTTP streaming to consume SSE events.
/// No polyfills needed — Dart's Stream and http package handle
/// streaming natively.
class OpenCodeClient {
  final ClientConfig config;
  final http.Client _restClient;
  final http.Client Function() _streamClientFactory;
  final bool _ownsRestClient;
  http.Client? _sseClient;
  StreamSubscription? _sseSubscription;

  OpenCodeClient(
    this.config, {
    http.Client? httpClient,
    http.Client Function()? streamClientFactory,
  })  : _restClient = httpClient ?? http.Client(),
        _streamClientFactory = streamClientFactory ?? http.Client.new,
        _ownsRestClient = httpClient == null;

  /// Throw a typed [ApiError] from an HTTP response.
  Never _throwForStatus(http.Response response, String context) {
    throw ApiError.fromResponse(
      response.statusCode,
      response.body,
      headers: response.headers,
    );
  }

  /// Encode Basic Auth header.
  String _encodeBasicAuth() {
    final credentials =
        base64Encode(utf8.encode('${config.username}:${config.password}'));
    return 'Basic $credentials';
  }

  Map<String, String> _headers({bool jsonBody = false}) {
    return {
      'Authorization': _encodeBasicAuth(),
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  Uri _uri(String path, {Map<String, String>? queryParameters}) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('${config.baseUrl}$normalizedPath');
    if (queryParameters == null || queryParameters.isEmpty) return uri;
    return uri.replace(queryParameters: {
      ...uri.queryParameters,
      ...queryParameters,
    });
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    String? rawBody,
    Map<String, String>? queryParameters,
    Duration? timeout,
    Set<int> expectedStatuses = const {200},
    required String context,
  }) async {
    final encodedBody = rawBody ?? (body != null ? jsonEncode(body) : null);
    final url = _uri(path, queryParameters: queryParameters);

    try {
      final future = switch (method) {
        'GET' => _restClient.get(url, headers: _headers()),
        'POST' => _restClient.post(
            url,
            headers: _headers(jsonBody: encodedBody != null),
            body: encodedBody,
          ),
        'PATCH' => _restClient.patch(
            url,
            headers: _headers(jsonBody: encodedBody != null),
            body: encodedBody,
          ),
        'DELETE' => _restClient.delete(url, headers: _headers()),
        _ => throw ArgumentError.value(
            method, 'method', 'Unsupported HTTP method'),
      };

      final response = await future.timeout(
        timeout ?? config.requestTimeout,
        onTimeout: () {
          throw ApiTimeoutError(message: '$context timed out');
        },
      );
      if (!expectedStatuses.contains(response.statusCode)) {
        _throwForStatus(response, context);
      }
      return response;
    } on ApiError {
      rethrow;
    } on TimeoutException {
      throw ApiTimeoutError(message: '$context timed out');
    } on http.ClientException catch (e) {
      throw ApiConnectionError(message: '$context connection failed: $e');
    } on Exception catch (e) {
      throw ApiConnectionError(message: '$context connection failed: $e');
    }
  }

  dynamic _decodeJson(http.Response response, String context) {
    try {
      return jsonDecode(response.body);
    } catch (e) {
      throw ApiError(
        statusCode: response.statusCode,
        message: '$context returned invalid JSON: $e',
        body: response.body,
        headers: response.headers,
      );
    }
  }

  Map<String, dynamic> _decodeMap(http.Response response, String context) {
    final data = _decodeJson(response, context);
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    throw ApiError(
      statusCode: response.statusCode,
      message: '$context returned ${data.runtimeType}, expected object',
      body: response.body,
      headers: response.headers,
    );
  }

  List<dynamic> _decodeListOrItems(http.Response response, String context) {
    final data = _decodeJson(response, context);
    if (data is Map && data['items'] is List) {
      return data['items'] as List<dynamic>;
    }
    if (data is List) return data;
    return [];
  }

  /// Verify credentials by hitting the health endpoint.
  Future<bool> verifyAuth() async {
    return (await checkConnection()).success;
  }

  Future<ConnectionCheckResult> checkConnection() async {
    try {
      await _request(
        'GET',
        '/global/health',
        timeout: config.connectTimeout,
        context: 'verify auth',
      );
      return const ConnectionCheckResult.success();
    } on AuthenticationError catch (e) {
      return ConnectionCheckResult.failure(
        'Authentication failed. Check username and password.',
        error: e,
      );
    } on ApiTimeoutError catch (e) {
      return ConnectionCheckResult.failure(
        'Connection timed out. Check server URL and network route.',
        error: e,
      );
    } on ApiConnectionError catch (e) {
      return ConnectionCheckResult.failure(
        'Server is unreachable. Check URL, ADB reverse, or Tailscale.',
        error: e,
      );
    } on ApiError catch (e) {
      return ConnectionCheckResult.failure(e.message, error: e);
    }
  }

  /// Subscribe to the OpenCode event stream.
  ///
  /// Returns a Stream of typed ChatEvent that can be listened to.
  /// The stream emits specific subclasses for each event type.
  ///
  /// Call [unsubscribe] to close the stream.
  Stream<ChatEvent> subscribeToEvents({String? directory}) {
    unsubscribe();

    final url = _uri(
      '/event',
      queryParameters: directory != null ? {'directory': directory} : null,
    );

    // Use a persistent client for the SSE connection
    _sseClient = _streamClientFactory();

    final request = http.Request('GET', url);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Authorization'] = _encodeBasicAuth();
    request.headers['Cache-Control'] = 'no-cache';

    // Send the request and get the streamed response
    final responseFuture = _sseClient!.send(request);

    late final StreamController<ChatEvent> controller;

    Timer? heartbeatTimer;
    var closed = false;

    Future<void> cleanup() async {
      if (closed) return;
      closed = true;
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      await _sseSubscription?.cancel();
      _sseSubscription = null;
      _sseClient?.close();
      _sseClient = null;
    }

    Future<void> closeStream({bool disconnected = false}) async {
      if (disconnected && !controller.isClosed) {
        controller.add(const DisconnectedEvent());
      }
      await cleanup();
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    controller = StreamController<ChatEvent>(
      onCancel: cleanup,
    );

    void resetHeartbeat() {
      heartbeatTimer?.cancel();
      heartbeatTimer = Timer(config.sseHeartbeatTimeout, () {
        debugPrint(
            '[PAI_SSE] Heartbeat timeout - no data for ${config.sseHeartbeatSeconds}s');
        unawaited(closeStream(disconnected: true));
      });
    }

    responseFuture.then((response) {
      if (closed || controller.isClosed) return;
      if (response.statusCode != 200) {
        controller.addError(
          ApiError.fromResponse(
              response.statusCode, response.reasonPhrase ?? ''),
        );
        unawaited(closeStream());
        return;
      }

      controller.add(const ConnectedEvent());
      resetHeartbeat();

      var currentEventType = '';
      var currentData = StringBuffer();

      final utf8Decoder = utf8.decoder;
      const lineSplitter = LineSplitter();

      _sseSubscription =
          response.stream.transform(utf8Decoder).transform(lineSplitter).listen(
        (line) {
          if (closed || controller.isClosed) return;
          resetHeartbeat();
          if (line.startsWith('event: ')) {
            currentEventType = line.substring(7);
          } else if (line.startsWith('data: ')) {
            if (currentData.isNotEmpty) {
              currentData.write('\n');
            }
            currentData.write(line.substring(6));
          } else if (line.isEmpty) {
            if (currentData.isNotEmpty) {
              final rawData = currentData.toString();
              debugPrint(
                  '[PAI_SSE_RAW] Event: $currentEventType | bytes=${rawData.length}');
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
          if (!closed && !controller.isClosed) {
            controller.add(ErrorEvent(
              error: error,
              message: error.toString(),
            ));
          }
          unawaited(closeStream());
        },
        onDone: () {
          unawaited(closeStream(disconnected: true));
        },
      );
    }).catchError((error) {
      if (!closed && !controller.isClosed) {
        controller.add(ErrorEvent(
          error: error,
          message: error.toString(),
        ));
      }
      unawaited(closeStream());
    });

    return controller.stream;
  }

  /// Close the SSE connection.
  void unsubscribe() {
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
  }

  void close() {
    unsubscribe();
    if (_ownsRestClient) {
      _restClient.close();
    }
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
  @visibleForTesting
  ChatEvent? buildTypedEventForTest(String eventName, String data) {
    return _buildTypedEvent(eventName, data);
  }

  /// Build a typed ChatEvent from raw SSE event data.
  ChatEvent? _buildTypedEvent(String eventName, String data) {
    if (eventName.isEmpty && data.isEmpty) return null;

    Map<String, dynamic>? parsed;
    String rawType = '';

    if (data.isNotEmpty) {
      try {
        parsed = jsonDecode(data) as Map<String, dynamic>;
        if (parsed['type'] is String) {
          rawType = parsed['type'] as String;
        }
      } catch (_) {
        // Data is not JSON, treat as plain string
      }
    }

    // Fallback to SSE event: header if JSON had no type field
    if (rawType.isEmpty) rawType = eventName;

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

  /// Create a new session, optionally scoped to [directory].
  Future<Map<String, dynamic>> createSession({
    String? title,
    String? directory,
  }) async {
    final response = await _request(
      'POST',
      '/session',
      queryParameters: directory != null ? {'directory': directory} : null,
      body: {if (title != null) 'title': title},
      context: 'create session',
    );
    return _decodeMap(response, 'create session');
  }

  /// Send a message to a session.
  ///
  /// Uses the correct endpoint: POST /session/{sessionID}/message
  /// Body: { "parts": [{"type": "text", "text": "..."}] }
  Future<void> sendMessage(String sessionId, String text,
      {String? directory}) async {
    await _request(
      'POST',
      '/session/$sessionId/message',
      queryParameters: directory != null ? {'directory': directory} : null,
      body: {
        'parts': [
          {'type': 'text', 'text': text}
        ]
      },
      expectedStatuses: const {200, 204},
      context: 'send message',
    );
  }

  Future<List<OpenCodeSession>> listSessionRecords({String? directory}) async {
    final response = await _request(
      'GET',
      '/session',
      queryParameters: directory != null ? {'directory': directory} : null,
      context: 'list sessions',
    );
    return _decodeListOrItems(response, 'list sessions')
        .whereType<Map>()
        .map(
            (item) => OpenCodeSession.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// List all sessions.
  Future<List<dynamic>> listSessions({String? directory}) async {
    final response = await _request(
      'GET',
      '/session',
      queryParameters: directory != null ? {'directory': directory} : null,
      context: 'list sessions',
    );
    return _decodeListOrItems(response, 'list sessions');
  }

  /// Update session metadata (title, etc).
  Future<void> updateSession(
    String sessionId, {
    String? title,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;

    await _request(
      'PATCH',
      '/session/$sessionId',
      body: body,
      context: 'update session',
    );
  }

  /// Delete a session.
  Future<void> deleteSession(String sessionId) async {
    await _request(
      'DELETE',
      '/session/$sessionId',
      expectedStatuses: const {200, 204},
      context: 'delete session',
    );
  }

  Future<List<OpenCodeMessageRecord>> getSessionMessageRecords(
      String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId/message',
      context: 'get messages',
    );
    return _decodeListOrItems(response, 'get messages')
        .whereType<Map>()
        .map((item) =>
            OpenCodeMessageRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// Fetch messages for a session.
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId/message',
      context: 'get messages',
    );
    return _decodeListOrItems(response, 'get messages');
  }

  /// Abort a running session (stop generation).
  Future<void> abortSession(String sessionId) async {
    await _request(
      'POST',
      '/session/$sessionId/abort',
      expectedStatuses: const {200, 204},
      context: 'abort session',
    );
  }

  Future<OpenCodeSession> getSessionRecord(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId',
      context: 'get session',
    );
    return OpenCodeSession.fromJson(_decodeMap(response, 'get session'));
  }

  /// Get session details (model, cost, tokens, etc).
  Future<Map<String, dynamic>> getSession(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId',
      context: 'get session',
    );
    return _decodeMap(response, 'get session');
  }

  Future<OpenCodeProviderRegistry> getProviderRegistry() async {
    return OpenCodeProviderRegistry(await getProviders());
  }

  /// List available providers and models.
  /// Tries `/config/providers` (SDK standard) first, falls back to `/provider`.
  Future<Map<String, dynamic>> getProviders() async {
    ApiError? lastError;
    for (final path in ['/config/providers', '/provider']) {
      try {
        final response = await _request(
          'GET',
          path,
          context: 'get providers',
        );
        return _decodeMap(response, 'get providers');
      } on ApiError catch (e) {
        lastError = e;
        // Try next endpoint; some server versions expose only one shape.
      }
    }
    throw lastError ??
        const ApiError(statusCode: 404, message: 'No providers endpoint found');
  }

  /// Send a message with optional model/parts override and advanced fields.
  Future<void> sendMessageAdvanced(
    String sessionId, {
    required List<Map<String, dynamic>> parts,
    Map<String, String>? model,
    String? agent,
    String? system,
    Map<String, bool>? tools,
    bool? noReply,
    String? messageId,
    String? directory,
  }) async {
    final body = <String, dynamic>{'parts': parts};
    if (model != null) body['model'] = model;
    if (agent != null) body['agent'] = agent;
    if (system != null) body['system'] = system;
    if (tools != null) body['tools'] = tools;
    if (noReply != null) body['noReply'] = noReply;
    if (messageId != null) body['messageID'] = messageId;

    await _request(
      'POST',
      '/session/$sessionId/message',
      queryParameters: directory != null ? {'directory': directory} : null,
      body: body,
      expectedStatuses: const {200, 204},
      context: 'send message advanced',
    );
  }

  /// Fork a session at a specific message.
  Future<Map<String, dynamic>> forkSession(
      String sessionId, String messageId) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/fork',
      body: {'messageID': messageId},
      context: 'fork session',
    );
    return _decodeMap(response, 'fork session');
  }

  /// Create or remove a share link for a session.
  Future<Map<String, dynamic>> shareSession(String sessionId) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/share',
      context: 'share session',
    );
    return _decodeMap(response, 'share session');
  }

  Future<void> unshareSession(String sessionId) async {
    await _request(
      'DELETE',
      '/session/$sessionId/share',
      expectedStatuses: const {200, 204},
      context: 'unshare session',
    );
  }

  /// Revert a message (undo file changes).
  Future<void> revertMessage(String sessionId, String messageId) async {
    await _request(
      'POST',
      '/session/$sessionId/revert',
      body: {'messageID': messageId},
      context: 'revert message',
    );
  }

  /// Unrevert messages in a session.
  Future<void> unrevertSession(String sessionId) async {
    await _request(
      'POST',
      '/session/$sessionId/unrevert',
      context: 'unrevert',
    );
  }

  Future<List<OpenCodeTodoItem>> getSessionTodoItems(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId/todo',
      context: 'get todos',
    );
    return _decodeListOrItems(response, 'get todos')
        .whereType<Map>()
        .map((item) =>
            OpenCodeTodoItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// Get session todos.
  Future<List<dynamic>> getSessionTodos(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId/todo',
      context: 'get todos',
    );
    return _decodeListOrItems(response, 'get todos');
  }

  Future<List<OpenCodeCommandItem>> getCommandItems() async {
    final response = await _request(
      'GET',
      '/command',
      context: 'get commands',
    );
    return _decodeListOrItems(response, 'get commands')
        .whereType<Map>()
        .map((item) =>
            OpenCodeCommandItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  /// List available slash commands.
  Future<List<dynamic>> getCommands() async {
    final response = await _request(
      'GET',
      '/command',
      context: 'get commands',
    );
    return _decodeListOrItems(response, 'get commands');
  }

  Future<List<OpenCodeFileMatch>> findFileMatches(
    String query, {
    int limit = 15,
    String? directory,
  }) async {
    return (await findFiles(query, limit: limit, directory: directory))
        .map(OpenCodeFileMatch.new)
        .toList();
  }

  /// Search for files/directories by fuzzy name match.
  Future<List<String>> findFiles(String query,
      {int limit = 15, String? directory}) async {
    final params = <String, String>{
      'query': query,
      'limit': '$limit',
    };
    if (directory != null) params['directory'] = directory;
    final response = await _request(
      'GET',
      '/find/file',
      queryParameters: params,
      context: 'find files',
    );
    return _decodeListOrItems(response, 'find files')
        .map((item) => item.toString())
        .toList();
  }

  /// Execute a slash command.
  Future<void> executeCommand(String sessionId, String command,
      {String? arguments}) async {
    final body = <String, dynamic>{'command': command};
    if (arguments != null) body['arguments'] = arguments;
    await _request(
      'POST',
      '/session/$sessionId/command',
      body: body,
      expectedStatuses: const {200, 204},
      context: 'execute command',
    );
  }

  /// Summarize a session.
  Future<Map<String, dynamic>> summarizeSession(
    String sessionId, {
    required String modelId,
    required String providerId,
  }) async {
    final response = await _request(
      'POST',
      '/session/$sessionId/summarize',
      body: {'modelID': modelId, 'providerID': providerId},
      context: 'summarize session',
    );
    return _decodeMap(response, 'summarize session');
  }

  /// Initialize a session (AGENTS.md).
  Future<void> initSession(
    String sessionId, {
    required String modelId,
    required String providerId,
  }) async {
    await _request(
      'POST',
      '/session/$sessionId/init',
      body: {'modelID': modelId, 'providerID': providerId},
      context: 'init session',
    );
  }

  /// Get child sessions (forked from this session).
  Future<List<dynamic>> getSessionChildren(String sessionId) async {
    final response = await _request(
      'GET',
      '/session/$sessionId/children',
      context: 'get session children',
    );
    return _decodeListOrItems(response, 'get session children');
  }

  /// Generic GET request.
  Future<http.Response> get(String path) async {
    return _request(
      'GET',
      path,
      context: 'GET $path',
    );
  }

  /// Generic POST request to an endpoint path.
  Future<http.Response> post(String path,
      {String? body, Duration? timeout}) async {
    return _request(
      'POST',
      path,
      rawBody: body,
      timeout: timeout,
      expectedStatuses: const {200, 204},
      context: 'POST $path',
    );
  }
}
