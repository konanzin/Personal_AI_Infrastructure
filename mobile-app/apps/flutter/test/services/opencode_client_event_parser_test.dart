import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pai_mobile_flutter/models/chat_event.dart';
import 'package:pai_mobile_flutter/services/api_errors.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';

class _OrderedFakeClient extends http.BaseClient {
  _OrderedFakeClient(this.name, this.log);

  final String name;
  final List<String> log;
  StreamController<List<int>>? controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    log.add('$name.send');
    controller = StreamController<List<int>>();
    return http.StreamedResponse(controller!.stream, 200);
  }

  @override
  void close() {
    log.add('$name.close');
    unawaited(controller?.close());
    super.close();
  }
}

class _FakeStreamClient extends http.BaseClient {
  bool closed = false;
  int sendCount = 0;
  StreamController<List<int>>? controller;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    sendCount++;
    controller = StreamController<List<int>>();
    return http.StreamedResponse(controller!.stream, 200);
  }

  @override
  void close() {
    closed = true;
    unawaited(controller?.close());
    super.close();
  }
}

void main() {
  late OpenCodeClient client;

  setUp(() {
    client = OpenCodeClient(ClientConfig(
      baseUrl: 'http://localhost:4096',
      username: 'test',
      password: 'test',
    ));
  });

  ChatEvent? parse(String eventName, Map<String, dynamic> payload) {
    return client.buildTypedEventForTest(eventName, jsonEncode(payload));
  }

  test('parses text delta events from SSE header fallback', () {
    final event = parse('session.next.text.delta', {
      'properties': {
        'sessionID': 'sess-1',
        'delta': 'hello',
      },
    });

    expect(event, isA<TextDeltaEvent>());
    final textEvent = event as TextDeltaEvent;
    expect(textEvent.delta, 'hello');
    expect(textEvent.sessionId, 'sess-1');
    expect(textEvent.originalEvent, 'session.next.text.delta');
  });

  test('parses shell lifecycle events', () {
    final started = parse('ignored.header', {
      'type': 'session.next.shell.started',
      'properties': {
        'sessionID': 'sess-1',
        'callID': 'sh-1',
        'command': 'ls -la',
      },
    });
    final ended = parse('session.next.shell.ended', {
      'properties': {
        'sessionID': 'sess-1',
        'callID': 'sh-1',
        'output': 'total 0',
      },
    });

    expect(started, isA<ShellStartedEvent>());
    expect((started as ShellStartedEvent).callId, 'sh-1');
    expect(started.command, 'ls -la');
    expect(started.sessionId, 'sess-1');

    expect(ended, isA<ShellEndedEvent>());
    expect((ended as ShellEndedEvent).callId, 'sh-1');
    expect(ended.output, 'total 0');
    expect(ended.sessionId, 'sess-1');
  });

  test('parses permission asked events', () {
    final event = parse('permission.asked', {
      'properties': {
        'id': 'perm-1',
        'sessionID': 'sess-1',
        'permission': 'write',
        'patterns': ['*.dart'],
        'metadata': {'path': 'lib/main.dart'},
        'always': ['read'],
        'tool': {'messageID': 'msg-1', 'callID': 'call-1'},
      },
    });

    expect(event, isA<PermissionAskedEvent>());
    final permissionEvent = event as PermissionAskedEvent;
    expect(permissionEvent.sessionId, 'sess-1');
    expect(permissionEvent.request.id, 'perm-1');
    expect(permissionEvent.request.permission, 'write');
    expect(permissionEvent.request.patterns, ['*.dart']);
    expect(permissionEvent.request.tool?.callID, 'call-1');
  });

  test('parses question asked and replied events', () {
    final asked = parse('question.asked', {
      'properties': {
        'id': 'q-1',
        'sessionID': 'sess-1',
        'questions': [
          {
            'question': 'Continue?',
            'header': 'Decision',
            'options': [
              {'label': 'Yes', 'description': 'Continue'},
              {'label': 'No', 'description': 'Stop'},
            ],
            'multiple': false,
            'custom': false,
          }
        ],
        'tool': {'messageID': 'msg-1', 'callID': 'call-q1'},
      },
    });
    final replied = parse('question.replied', {
      'properties': {
        'sessionID': 'sess-1',
        'requestID': 'q-1',
        'answers': [
          ['Yes']
        ],
      },
    });

    expect(asked, isA<QuestionAskedEvent>());
    final askedEvent = asked as QuestionAskedEvent;
    expect(askedEvent.sessionId, 'sess-1');
    expect(askedEvent.request.id, 'q-1');
    expect(askedEvent.request.questions.first.question, 'Continue?');
    expect(askedEvent.request.questions.first.options.last.label, 'No');
    expect(askedEvent.request.tool?.callID, 'call-q1');

    expect(replied, isA<QuestionRepliedEvent>());
    final repliedEvent = replied as QuestionRepliedEvent;
    expect(repliedEvent.sessionId, 'sess-1');
    expect(repliedEvent.requestId, 'q-1');
    expect(repliedEvent.answers, [
      ['Yes']
    ]);
  });

  test('wraps unknown JSON events as status events', () {
    final event = parse('ignored.header', {
      'type': 'opencode.future.event',
      'properties': {'sessionID': 'sess-1', 'newShape': true},
    });

    expect(event, isA<StatusEvent>());
    final status = event as StatusEvent;
    expect(status.originalEvent, 'opencode.future.event');
    expect(status.sessionId, 'sess-1');
    expect(status.payload['properties'], isA<Map<String, dynamic>>());
  });

  test('does not throw on non-map or malformed JSON payloads', () {
    expect(
      () => client.buildTypedEventForTest('session.status', '[]'),
      returnsNormally,
    );
    expect(
      () => client.buildTypedEventForTest('session.status', '"hello"'),
      returnsNormally,
    );
    expect(
      () => client.buildTypedEventForTest('session.status', 'not-json'),
      returnsNormally,
    );
  });

  test('parses malformed permission payload defensively', () {
    final event = parse('permission.asked', {
      'properties': {
        'id': 123,
        'sessionID': 'sess-1',
        'permission': null,
        'patterns': ['*.dart', 42],
        'metadata': 'unexpected',
        'always': [true],
        'tool': {'messageID': 99, 'callID': 2},
      },
    });

    expect(event, isA<PermissionAskedEvent>());
    final permission = event as PermissionAskedEvent;
    expect(permission.request.id, '123');
    expect(permission.request.permission, '');
    expect(permission.request.patterns, ['*.dart', '42']);
    expect(permission.request.metadata, isEmpty);
    expect(permission.request.always, ['true']);
    expect(permission.request.tool?.messageID, '99');
    expect(permission.request.tool?.callID, '2');
  });

  test('parses malformed question payload defensively', () {
    final event = parse('question.asked', {
      'properties': {
        'id': 'q-1',
        'sessionID': 'sess-1',
        'questions': [
          'bad-row',
          {
            'question': 42,
            'header': null,
            'options': [
              'bad-option',
              {'label': 1, 'description': false},
            ],
            'multiple': 'yes',
            'custom': 1,
          },
        ],
        'tool': {'messageID': 'msg-1', 'callID': 7},
      },
    });

    expect(event, isA<QuestionAskedEvent>());
    final asked = event as QuestionAskedEvent;
    expect(asked.request.questions.length, 1);
    expect(asked.request.questions.single.question, '42');
    expect(asked.request.questions.single.header, '');
    expect(asked.request.questions.single.multiple, isFalse);
    expect(asked.request.questions.single.custom, isFalse);
    expect(asked.request.questions.single.options.single.label, '1');
    expect(asked.request.questions.single.options.single.description, 'false');
    expect(asked.request.tool?.callID, '7');
  });

  test('parses malformed tool payloads defensively', () {
    final event = parse('session.next.tool.success', {
      'properties': {
        'callID': 42,
        'structured': 'not-a-map',
        'content': [
          'bad-content',
          {'type': 'text', 'text': 'ok'},
        ],
        'provider': ['bad'],
      },
    });

    expect(event, isA<ToolCallSuccessEvent>());
    final success = event as ToolCallSuccessEvent;
    expect(success.callId, '42');
    expect(success.structured, isEmpty);
    expect(success.content, [
      {'type': 'text', 'text': 'ok'}
    ]);
    expect(success.provider, isEmpty);
  });

  group('OpenCodeClient transport', () {
    test('normalizes server URLs before requests', () {
      final config = ClientConfig(
        baseUrl: 'localhost:4096/',
        username: 'test',
        password: 'test',
      );

      expect(config.baseUrl, 'http://localhost:4096');
    });

    test('sendMessage sends auth, JSON body, directory and applies timeout',
        () async {
      late http.Request capturedRequest;
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
          requestTimeoutSeconds: 1,
        ),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response('', 204);
        }),
      );

      await client.sendMessage('sess-1', 'hello', directory: '/tmp/work');

      expect(capturedRequest.method, 'POST');
      expect(capturedRequest.url.path, '/session/sess-1/message');
      expect(capturedRequest.url.queryParameters['directory'], '/tmp/work');
      expect(capturedRequest.headers['Authorization'], startsWith('Basic '));
      expect(capturedRequest.headers['Content-Type'],
          contains('application/json'));
      expect(jsonDecode(capturedRequest.body), {
        'parts': [
          {'type': 'text', 'text': 'hello'}
        ]
      });
    });

    test('sendMessageAdvanced preserves model override contract', () async {
      late Map<String, dynamic> body;
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        httpClient: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('', 200);
        }),
      );

      await client.sendMessageAdvanced(
        'sess-1',
        parts: [
          {'type': 'text', 'text': 'hello'}
        ],
        model: {'providerID': 'kimi-for-coding', 'modelID': 'k2p6'},
      );

      expect(body['model'], {
        'providerID': 'kimi-for-coding',
        'modelID': 'k2p6',
      });
      expect(body['parts'], [
        {'type': 'text', 'text': 'hello'}
      ]);
    });

    test('sendMessage timeout is surfaced as ApiTimeoutError', () async {
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
          requestTimeoutSeconds: 0,
        ),
        httpClient: MockClient((request) => Completer<http.Response>().future),
      );

      await expectLater(
        client.sendMessage('sess-1', 'hello'),
        throwsA(isA<ApiTimeoutError>()),
      );
    });

    test('checkConnection returns auth-specific diagnostics', () async {
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'bad',
        ),
        httpClient: MockClient((request) async => http.Response('nope', 401)),
      );

      final result = await client.checkConnection();

      expect(result.success, isFalse);
      expect(result.message, contains('Authentication failed'));
      expect(result.error, isA<AuthenticationError>());
    });

    test('getProviders falls back from config providers to provider endpoint',
        () async {
      final paths = <String>[];
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        httpClient: MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path == '/config/providers') {
            return http.Response('missing', 404);
          }
          return http.Response(
            jsonEncode({
              'kimi-for-coding': {
                'models': ['k2p6']
              }
            }),
            200,
          );
        }),
      );

      final providers = await client.getProviders();

      expect(paths, ['/config/providers', '/provider']);
      expect(providers.keys, contains('kimi-for-coding'));
    });

    test('listSessionRecords exposes typed session data', () async {
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'sess-1',
                  'title': 'Mobile smoke',
                  'directory': '/tmp/work',
                }
              ]
            }),
            200,
          );
        }),
      );

      final sessions = await client.listSessionRecords();

      expect(sessions.single.id, 'sess-1');
      expect(sessions.single.title, 'Mobile smoke');
      expect(sessions.single.directory, '/tmp/work');
      expect(sessions.single.raw['id'], 'sess-1');
    });

    test('SSE subscription cancellation closes stream client', () async {
      final streamClient = _FakeStreamClient();
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        streamClientFactory: () => streamClient,
      );

      final subscription = client.subscribeToEvents().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      expect(streamClient.sendCount, 1);
      expect(streamClient.closed, isTrue);
    });

    test('listFiles parses FileNode entries and scopes by directory', () async {
      late http.Request capturedRequest;
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        httpClient: MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            jsonEncode([
              {
                'name': 'src',
                'path': 'src',
                'absolute': '/home/user/proj/src',
                'type': 'directory',
                'ignored': false,
              },
              {
                'name': 'readme.md',
                'path': 'readme.md',
                'absolute': '/home/user/proj/readme.md',
                'type': 'file',
                'ignored': false,
              },
              {
                'name': '.git',
                'path': '.git',
                'absolute': '/home/user/proj/.git',
                'type': 'directory',
                'ignored': true,
              },
            ]),
            200,
          );
        }),
      );

      final nodes = await client.listFiles(directory: '/home/user/proj');

      expect(capturedRequest.url.path, '/file');
      expect(capturedRequest.url.queryParameters['path'], '.');
      expect(
          capturedRequest.url.queryParameters['directory'], '/home/user/proj');
      expect(nodes.length, 3);
      expect(nodes[0].isDirectory, isTrue);
      expect(nodes[0].absolute, '/home/user/proj/src');
      expect(nodes[1].isDirectory, isFalse);
      expect(nodes[2].ignored, isTrue);
    });

    test('resubscribe tears down previous stream before connecting', () async {
      final log = <String>[];
      var n = 0;
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        streamClientFactory: () => _OrderedFakeClient('c${++n}', log),
      );

      final sub1 = client.subscribeToEvents().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      final sub2 = client.subscribeToEvents().listen((_) {});
      await Future<void>.delayed(Duration.zero);

      expect(log, containsAllInOrder(['c1.send', 'c1.close', 'c2.send']));
      await sub1.cancel();
      await sub2.cancel();
    });

    test('unsubscribe future completes with stream client closed', () async {
      final log = <String>[];
      final client = OpenCodeClient(
        ClientConfig(
          baseUrl: 'http://localhost:4096',
          username: 'user',
          password: 'pass',
        ),
        streamClientFactory: () => _OrderedFakeClient('c1', log),
      );

      client.subscribeToEvents().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await client.unsubscribe();

      expect(log, contains('c1.close'));
    });
  });
}
