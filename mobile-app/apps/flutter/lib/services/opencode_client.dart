import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/chat_event.dart';
import 'api_errors.dart';
import 'sse_payload_parsing.dart' as sse;

const bool _verboseSseRaw =
    bool.fromEnvironment('PAI_SSE_VERBOSE', defaultValue: false);

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

/// One entry of a directory listing (`GET /file` → FileNode).
class OpenCodeFileNode {
  final String name;
  final String path;
  final String absolute;
  final bool isDirectory;
  final bool ignored;

  const OpenCodeFileNode({
    required this.name,
    required this.path,
    required this.absolute,
    required this.isDirectory,
    required this.ignored,
  });

  factory OpenCodeFileNode.fromJson(Map<String, dynamic> json) {
    return OpenCodeFileNode(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      absolute: json['absolute'] as String? ?? '',
      isDirectory: json['type'] == 'directory',
      ignored: json['ignored'] as bool? ?? false,
    );
  }
}

class OpenCodeProviderRegistry {
  final Map<String, dynamic> raw;

  const OpenCodeProviderRegistry(this.raw);

  Iterable<String> get providerIds => raw.keys;

  /// Flat, sorted list of `provider/model` identifiers across all providers —
  /// the same shape `opencode models` prints and that classifier.json expects.
  ///
  /// Defensive about the response shape: `/config/providers` returns
  /// `{providers: [{id, models: {..}|[..]}, ...]}`, while older/`/provider`
  /// shapes may be a flat `id -> data` map. `models` may be a map keyed by
  /// model id or a list of ids / `{id|name}` objects.
  List<String> get modelIds {
    final providers = <Map<String, dynamic>>[];
    final declared = raw['providers'];
    if (declared is List) {
      providers.addAll(
          declared.whereType<Map>().map((m) => Map<String, dynamic>.from(m)));
    } else {
      for (final entry in raw.entries) {
        if (entry.value is Map) {
          providers.add({
            'id': entry.key,
            ...Map<String, dynamic>.from(entry.value as Map),
          });
        }
      }
    }

    final ids = <String>{};
    for (final provider in providers) {
      final providerId = provider['id']?.toString();
      if (providerId == null || providerId.isEmpty) continue;
      final models = provider['models'];
      if (models is Map) {
        for (final key in models.keys) {
          ids.add('$providerId/$key');
        }
      } else if (models is List) {
        for (final model in models) {
          final modelId = model is Map
              ? (model['id'] ?? model['name'])?.toString()
              : model?.toString();
          if (modelId != null && modelId.isNotEmpty) {
            ids.add('$providerId/$modelId');
          }
        }
      }
    }

    final sorted = ids.toList()..sort();
    return sorted;
  }
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

  /// Close handle of the active SSE generation, so [unsubscribe] can run the
  /// full teardown (controller close included) and callers can await it.
  Future<void> Function()? _activeSseClose;

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

  Map<String, String> _headers({
    bool jsonBody = false,
    Map<String, String>? extra,
  }) {
    return {
      'Authorization': _encodeBasicAuth(),
      if (jsonBody) 'Content-Type': 'application/json',
      ...?extra,
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
    Map<String, String>? extraHeaders,
    Duration? timeout,
    Set<int> expectedStatuses = const {200},
    required String context,
  }) async {
    final encodedBody = rawBody ?? (body != null ? jsonEncode(body) : null);
    final url = _uri(path, queryParameters: queryParameters);

    try {
      final future = switch (method) {
        'GET' => _restClient.get(url, headers: _headers(extra: extraHeaders)),
        'POST' => _restClient.post(
            url,
            headers:
                _headers(jsonBody: encodedBody != null, extra: extraHeaders),
            body: encodedBody,
          ),
        'PUT' => _restClient.put(
            url,
            headers:
                _headers(jsonBody: encodedBody != null, extra: extraHeaders),
            body: encodedBody,
          ),
        'PATCH' => _restClient.patch(
            url,
            headers:
                _headers(jsonBody: encodedBody != null, extra: extraHeaders),
            body: encodedBody,
          ),
        'DELETE' =>
          _restClient.delete(url, headers: _headers(extra: extraHeaders)),
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
    // Serialize generations: the previous stream finishes tearing down before
    // the new connection is attempted, so two SSE connections never overlap.
    final previousTeardown = unsubscribe().catchError((_) {});

    final url = _uri(
      '/event',
      queryParameters: directory != null ? {'directory': directory} : null,
    );

    // Use a persistent client for the SSE connection
    final sseClient = _streamClientFactory();
    _sseClient = sseClient;

    final request = http.Request('GET', url);
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Authorization'] = _encodeBasicAuth();
    request.headers['Cache-Control'] = 'no-cache';

    // Send the request and get the streamed response
    final responseFuture =
        previousTeardown.then((_) => sseClient.send(request));

    late final StreamController<ChatEvent> controller;

    StreamSubscription<String>? subscription;
    Timer? heartbeatTimer;
    var closed = false;

    Future<void> cleanup() async {
      if (closed) return;
      closed = true;
      heartbeatTimer?.cancel();
      heartbeatTimer = null;
      // Tear down only THIS call's resources. A newer subscribeToEvents call
      // may already have replaced the instance fields; touching them blindly
      // here would kill the new stream (the await below yields, so this
      // continuation can run after a resubscribe).
      final sub = subscription;
      subscription = null;
      if (identical(_sseSubscription, sub)) _sseSubscription = null;
      if (identical(_sseClient, sseClient)) _sseClient = null;
      await sub?.cancel();
      sseClient.close();
    }

    Future<void> closeStream({bool disconnected = false}) async {
      if (disconnected && !controller.isClosed) {
        controller.add(const DisconnectedEvent());
      }
      await cleanup();
      if (!controller.isClosed) {
        // Don't await: close()'s future only completes once a listener
        // consumes the done event, and a never-listened stream would block
        // the awaited teardown (and with it the next subscribe) forever.
        unawaited(controller.close());
      }
    }

    controller = StreamController<ChatEvent>(
      onCancel: cleanup,
    );
    _activeSseClose = closeStream;

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

      subscription =
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
              if (_verboseSseRaw) {
                debugPrint(
                    '[PAI_SSE_RAW] Event: $currentEventType | bytes=${rawData.length}');
              }
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
      _sseSubscription = subscription;
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

  /// Close the SSE connection. The returned future completes when the
  /// previous stream (subscription, HTTP client and controller) is fully
  /// torn down; awaiting it before resubscribing prevents overlap.
  Future<void> unsubscribe() {
    final close = _activeSseClose;
    _activeSseClose = null;
    if (close != null) return close();
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseClient?.close();
    _sseClient = null;
    return Future.value();
  }

  void close() {
    unawaited(unsubscribe().catchError((_) {}));
    if (_ownsRestClient) {
      _restClient.close();
    }
  }

  /// Build a typed ChatEvent from raw SSE event data.
  @visibleForTesting
  ChatEvent? buildTypedEventForTest(String eventName, String data) {
    return _buildTypedEvent(eventName, data);
  }

  /// Build a typed ChatEvent from raw SSE event data.
  ChatEvent? _buildTypedEvent(String eventName, String data) {
    if (eventName.isEmpty && data.isEmpty) return null;

    final parsed = data.isNotEmpty ? sse.asPayloadMap(data) : null;
    // Fallback to SSE event: header if JSON had no type field.
    final rawType = _string(parsed?['type']) ?? eventName;

    final sessionId = parsed != null ? sse.extractSessionId(parsed) : null;

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
            callId: _string(props['callID']) ?? '',
            toolName: _string(props['name']) ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.input.delta':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallInputDeltaEvent(
            callId: _string(props['callID']) ?? '',
            delta: _string(props['delta']) ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.input.ended':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallInputEndedEvent(
            callId: _string(props['callID']) ?? '',
            text: _string(props['text']) ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.called':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallCalledEvent(
            callId: _string(props['callID']) ?? '',
            toolName: _string(props['tool']) ?? '',
            input: _mapOrEmpty(props['input']),
            provider: _mapOrEmpty(props['provider']),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.progress':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallProgressEvent(
            callId: _string(props['callID']) ?? '',
            structured: _mapOrEmpty(props['structured']),
            content: _mapListOrEmpty(props['content']),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.success':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ToolCallSuccessEvent(
            callId: _string(props['callID']) ?? '',
            structured: _mapOrEmpty(props['structured']),
            content: _mapListOrEmpty(props['content']),
            provider: _mapOrEmpty(props['provider']),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.tool.failed':
        final props = _extractProperties(parsed);
        if (props != null) {
          final error = _mapOrEmpty(props['error']);
          return ToolCallFailedEvent(
            callId: _string(props['callID']) ?? '',
            errorMessage: _string(error['message']) ?? 'Unknown error',
            provider: _mapOrEmpty(props['provider']),
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.shell.started':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ShellStartedEvent(
            callId: _string(props['callID']) ?? '',
            command: _string(props['command']) ?? '',
            sessionId: sessionId,
            originalEvent: rawType,
          );
        }
        break;

      case 'session.next.shell.ended':
        final props = _extractProperties(parsed);
        if (props != null) {
          return ShellEndedEvent(
            callId: _string(props['callID']) ?? '',
            output: _string(props['output']) ?? '',
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
            requestId: _string(props['requestID']) ?? '',
            reply: _string(props['reply']) ?? '',
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
          final answers = _stringMatrixOrEmpty(props['answers']);
          return QuestionRepliedEvent(
            requestId: _string(props['requestID']) ?? '',
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
            requestId: _string(props['requestID']) ?? '',
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
        final text = _string(delta['text']);
        if (text != null) return text;
      }
    }
    final delta = parsed?['delta'];
    if (delta is String) return delta;
    if (delta is Map) {
      final text = _string(delta['text']);
      if (text != null) return text;
    }
    return null;
  }

  /// Extract text from event.
  String? _extractText(Map<String, dynamic>? parsed) {
    final props = _extractProperties(parsed);
    if (props != null) {
      final text = _string(props['text']);
      if (text != null) return text;
    }
    return _string(parsed?['text']);
  }

  /// Extract reasoning ID from event.
  String? _extractReasoningId(Map<String, dynamic>? parsed) {
    final props = _extractProperties(parsed);
    if (props != null) {
      final id = _string(props['reasoningID']);
      if (id != null) return id;
    }
    return null;
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  Map<String, dynamic> _mapOrEmpty(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  List<Map<String, dynamic>> _mapListOrEmpty(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  List<List<String>> _stringMatrixOrEmpty(dynamic value) {
    if (value is! List) return const [];
    return [
      for (final row in value)
        if (row is List) [for (final item in row) _string(item) ?? ''],
    ];
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
  ///
  /// [agent] selects the server-side agent profile for this message only
  /// (e.g. `build-mobile` for the lean PAI delivery profile). The session
  /// keeps its default when null, so desktop↔mobile handoff is unaffected.
  Future<void> sendMessage(String sessionId, String text,
      {String? directory, String? agent}) async {
    await _request(
      'POST',
      '/session/$sessionId/message',
      queryParameters: directory != null ? {'directory': directory} : null,
      body: {
        if (agent != null) 'agent': agent,
        'parts': [
          {'type': 'text', 'text': text}
        ]
      },
      expectedStatuses: const {200, 204},
      context: 'send message',
    );
  }

  /// List the agent names available on this server (GET /agent).
  Future<Set<String>> listAgentNames() async {
    final response = await _request(
      'GET',
      '/agent',
      context: 'list agents',
    );
    return _decodeListOrItems(response, 'list agents')
        .whereType<Map>()
        .map((item) => item['name'])
        .whereType<String>()
        .toSet();
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

  // ── PTY (Termius-style terminal over the OpenCode runtime plane) ───────

  Map<String, String>? _ptyQuery(String? directory) =>
      directory != null && directory.isNotEmpty
          ? {'directory': directory}
          : null;

  /// List PTY sessions, optionally scoped to a directory.
  Future<List<dynamic>> listPtys({String? directory}) async {
    final response = await _request(
      'GET',
      '/pty',
      queryParameters: _ptyQuery(directory),
      context: 'list ptys',
    );
    return _decodeListOrItems(response, 'list ptys');
  }

  /// Create a PTY running the user's shell in [directory].
  Future<Map<String, dynamic>> createPty({
    String? directory,
    String? command,
    String? title,
  }) async {
    final response = await _request(
      'POST',
      '/pty',
      queryParameters: _ptyQuery(directory),
      body: {
        if (command != null) 'command': command,
        if (title != null) 'title': title,
      },
      context: 'create pty',
    );
    return _decodeMap(response, 'create pty');
  }

  /// Terminate a PTY session.
  Future<void> deletePty(String ptyId, {String? directory}) async {
    await _request(
      'DELETE',
      '/pty/$ptyId',
      queryParameters: _ptyQuery(directory),
      context: 'delete pty',
    );
  }

  /// Resize a PTY to match the client terminal dimensions.
  Future<void> resizePty(
    String ptyId, {
    required int rows,
    required int cols,
    String? directory,
  }) async {
    await _request(
      'PUT',
      '/pty/$ptyId',
      queryParameters: _ptyQuery(directory),
      body: {
        'size': {'rows': rows, 'cols': cols},
      },
      context: 'resize pty',
    );
  }

  /// Issue a short-lived WebSocket connect ticket for a PTY.
  /// The server requires the `x-opencode-ticket: 1` marker header.
  Future<String> getPtyConnectTicket(String ptyId, {String? directory}) async {
    final response = await _request(
      'POST',
      '/pty/$ptyId/connect-token',
      queryParameters: _ptyQuery(directory),
      extraHeaders: const {'x-opencode-ticket': '1'},
      context: 'pty connect token',
    );
    final ticket = _decodeMap(response, 'pty connect token')['ticket'];
    if (ticket is! String || ticket.isEmpty) {
      throw ApiError(
        statusCode: response.statusCode,
        message: 'pty connect token missing ticket',
        body: response.body,
      );
    }
    return ticket;
  }

  /// WebSocket URI for a PTY connection. The [ticket] authenticates the
  /// socket (Basic Auth headers are not used on this endpoint); [cursor]
  /// resumes output from a previous connection.
  Uri ptyConnectUri(
    String ptyId, {
    required String ticket,
    int? cursor,
    String? directory,
  }) {
    final base = _uri('/pty/$ptyId/connect', queryParameters: {
      'ticket': ticket,
      if (cursor != null) 'cursor': '$cursor',
      ...?_ptyQuery(directory),
    });
    return base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');
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

  /// List the entries of a directory (`GET /file`).
  ///
  /// [path] is resolved by the server relative to [directory] (the scope
  /// root); pass `.` with `directory` set to an absolute path to list that
  /// path. Returns files and directories.
  Future<List<OpenCodeFileNode>> listFiles({
    String path = '.',
    String? directory,
  }) async {
    final params = <String, String>{'path': path};
    if (directory != null) params['directory'] = directory;
    final response = await _request(
      'GET',
      '/file',
      queryParameters: params,
      context: 'list files',
    );
    return _decodeListOrItems(response, 'list files')
        .whereType<Map>()
        .map((item) =>
            OpenCodeFileNode.fromJson(Map<String, dynamic>.from(item)))
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
