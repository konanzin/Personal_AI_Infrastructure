import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pai_mobile_flutter/models/chat_event.dart';
import 'package:pai_mobile_flutter/models/chat_message.dart';
import 'package:pai_mobile_flutter/models/message_part.dart';
import 'package:pai_mobile_flutter/providers/opencode_provider.dart';
import 'package:pai_mobile_flutter/services/connectivity_service.dart';
import 'package:pai_mobile_flutter/services/api_errors.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';

class _FakeOpenCodeClient extends OpenCodeClient {
  _FakeOpenCodeClient() : super(_dummyConfig);

  static final ClientConfig _dummyConfig = ClientConfig(
    baseUrl: 'http://localhost:4096',
    username: 'test',
    password: 'test',
  );

  Object? getSessionMessagesError;
  List<dynamic> getSessionMessagesResult = [];
  int getSessionMessagesCallCount = 0;

  /// When set, [getSessionMessages] suspends until the gate completes so
  /// tests can interleave a session switch with an in-flight fetch.
  Completer<void>? getSessionMessagesGate;

  @override
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    getSessionMessagesCallCount++;
    final gate = getSessionMessagesGate;
    if (gate != null) await gate.future;
    if (getSessionMessagesError != null) {
      throw getSessionMessagesError!;
    }
    return getSessionMessagesResult;
  }

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async => {};

  @override
  Future<List<dynamic>> getSessionTodos(String sessionId) async => [];

  @override
  Future<Map<String, dynamic>> createSession(
          {String? title, String? directory}) async =>
      {'id': 'sess-1'};

  @override
  Future<void> unsubscribe() => Future.value();

  /// When set, [subscribeToEvents] returns this controller's stream so tests
  /// can push live SSE events.
  StreamController<ChatEvent>? eventController;

  @override
  Stream<ChatEvent> subscribeToEvents({String? directory}) =>
      eventController?.stream ?? const Stream.empty();

  Object? sendMessageError;
  int sendMessageCallCount = 0;
  String? lastSentAgent;
  @override
  Future<void> sendMessage(String sessionId, String text,
      {String? directory, String? agent}) async {
    sendMessageCallCount++;
    lastSentAgent = agent;
    if (sendMessageError != null) {
      throw sendMessageError!;
    }
  }

  /// Agents the fake server reports; empty by default so existing tests
  /// exercise the no-agent path.
  Set<String> availableAgents = {};
  @override
  Future<Set<String>> listAgentNames() async => availableAgents;

  @override
  Future<http.Response> post(String path,
          {String? body, Duration? timeout}) async =>
      http.Response('', 200);

  @override
  Future<List<dynamic>> getCommands() async => [];

  @override
  Future<List<String>> findFiles(String query,
          {int limit = 15, String? directory}) async =>
      [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  group('OpenCodeProvider connectivity', () {
    late OpenCodeProvider provider;
    late _FakeOpenCodeClient fakeClient;

    setUp(() {
      fakeClient = _FakeOpenCodeClient();
      provider = OpenCodeProvider(client: fakeClient, sessionId: 'sess-1');
    });

    tearDown(() {
      provider.dispose();
    });

    test('loadHistory success marks ConnectionStatus.online', () async {
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'role': 'user', 'id': 'msg-1'},
          'parts': [
            {'type': 'text', 'text': 'hello'}
          ],
        }
      ];

      await provider.loadHistory();

      expect(provider.connectionState, ConnectionStatus.online);
    });

    test('loadHistory failure does not mark online and propagates error',
        () async {
      fakeClient.getSessionMessagesError = Exception('network down');

      await expectLater(provider.loadHistory(), throwsA(isA<Exception>()));
      expect(provider.connectionState, isNot(ConnectionStatus.online));
      expect(provider.lastError, contains('network down'));
    });

    test('reconnect success marks online', () async {
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'role': 'user', 'id': 'msg-1'},
          'parts': [
            {'type': 'text', 'text': 'hello'}
          ],
        }
      ];

      await provider.reconnect();

      expect(provider.connectionState, ConnectionStatus.online);
    });

    test('reconnect with getSessionMessages failing never goes online',
        () async {
      fakeClient.getSessionMessagesError = Exception('server error');

      await provider.reconnect();

      expect(provider.connectionState, isNot(ConnectionStatus.online));
      expect(fakeClient.getSessionMessagesCallCount, greaterThan(0));
    });

    test('send timeout does not retry non-idempotent message post', () async {
      fakeClient.sendMessageError =
          const ApiTimeoutError(message: 'send message timed out');

      final subscription = provider.sendMessageStream('hello').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await subscription.cancel();

      expect(fakeClient.sendMessageCallCount, 1);
      expect(provider.lastError, contains('send message timed out'));
    });

    test('sends build-mobile agent when the server defines it', () async {
      fakeClient.availableAgents = {'build', 'build-mobile'};

      final subscription = provider.sendMessageStream('hello').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      expect(fakeClient.sendMessageCallCount, 1);
      expect(fakeClient.lastSentAgent, 'build-mobile');
    });

    test('sends without agent when the server does not define build-mobile',
        () async {
      fakeClient.availableAgents = {'build'};

      final subscription = provider.sendMessageStream('hello').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await subscription.cancel();

      expect(fakeClient.sendMessageCallCount, 1);
      expect(fakeClient.lastSentAgent, isNull);
    });
  });

  group('OpenCodeProvider history parsing', () {
    late OpenCodeProvider provider;
    late _FakeOpenCodeClient fakeClient;

    setUp(() {
      fakeClient = _FakeOpenCodeClient();
      provider = OpenCodeProvider(client: fakeClient, sessionId: 'sess-1');
    });

    tearDown(() {
      provider.dispose();
    });

    test('associates tool calls, reasoning and questions from history',
        () async {
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'role': 'assistant', 'id': 'msg-a1', 'time': 1710000000000},
          'parts': [
            {'type': 'reasoning', 'text': 'Let me think...'},
            {
              'type': 'tool',
              'id': 'part-t1',
              'callID': 'call-1',
              'tool': 'myTool',
              'state': {
                'status': 'completed',
                'input': {'foo': 'bar'},
                'output': 'tool output',
              },
            },
            {
              'type': 'text',
              'text': 'Here is the result.',
            },
          ],
        },
        {
          'info': {'role': 'user', 'id': 'msg-u1', 'time': 1710000001000},
          'parts': [
            {'type': 'text', 'text': 'thanks'},
          ],
        },
      ];

      await provider.loadHistory();

      // Reasoning attached to assistant message
      expect(provider.getReasoningForMessage('msg-a1'), 'Let me think...');

      // Tool call attached
      final toolCalls = provider.getToolCallsForMessage('msg-a1');
      expect(toolCalls.length, 1);
      expect(toolCalls.first.name, 'myTool');
      expect(toolCalls.first.id, 'call-1');
      expect(toolCalls.first.content, hasLength(1));
      expect((toolCalls.first.content.first as ToolTextContent).text,
          'tool output');

      // Text present in history
      final history = provider.history.toList();
      expect(history.length, 2);
      expect(history[0].text?.contains('Here is the result.'), isTrue);
      expect(history[1].text, 'thanks');
    });

    test('parses answered question tool into answered questions', () async {
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'role': 'assistant', 'id': 'msg-a2'},
          'parts': [
            {
              'type': 'tool',
              'id': 'part-q1',
              'callID': 'call-q1',
              'tool': 'question',
              'state': {
                'status': 'completed',
                'input': {
                  'questions': [
                    {
                      'question': 'What?',
                      'header': 'Pick',
                      'options': [
                        {'label': 'A', 'description': 'Option A'},
                      ],
                      'multiple': false,
                      'custom': false,
                    }
                  ]
                },
                'output': '"What?"="A"',
              },
            },
          ],
        },
      ];

      await provider.loadHistory();

      final answered = provider.getAnsweredQuestionsForMessage('msg-a2');
      expect(answered.length, 1);
      expect(answered.first.request.questions.first.question, 'What?');
      expect(answered.first.answers.first.first, 'A');
    });

    test('persisted live answer equal to history tool part does not duplicate',
        () async {
      // A mesma pergunta existe no histórico (chave callID) e na persistência
      // da resposta ao vivo (chave requestId) — deve render um único chip.
      final persisted = {
        'qst-live-1': {
          'answers': [
            ['A']
          ],
          'msgId': 'msg-a2',
          'offset': 0,
          'questions': [
            {
              'question': 'What?',
              'header': 'Pick',
              'options': [
                {'label': 'A', 'description': 'Option A'},
              ],
              'multiple': false,
              'custom': false,
            }
          ],
          'sessionID': 'sess-1',
        },
      };
      const channel =
          MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'read') {
          final args = call.arguments as Map<Object?, Object?>;
          if (args['key'] == 'answered_sess-1') {
            return jsonEncode(persisted);
          }
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async => null);
      });

      fakeClient.getSessionMessagesResult = [
        {
          'info': {'role': 'assistant', 'id': 'msg-a2'},
          'parts': [
            {
              'type': 'tool',
              'id': 'part-q1',
              'callID': 'call-q1',
              'tool': 'question',
              'state': {
                'status': 'completed',
                'input': {
                  'questions': [
                    {
                      'question': 'What?',
                      'header': 'Pick',
                      'options': [
                        {'label': 'A', 'description': 'Option A'},
                      ],
                      'multiple': false,
                      'custom': false,
                    }
                  ]
                },
                'output': '"What?"="A"',
              },
            },
          ],
        },
      ];

      await provider.loadHistory();

      final answered = provider.getAnsweredQuestionsForMessage('msg-a2');
      expect(answered.length, 1);
    });
  });

  group('OpenCodeProvider live tool streaming', () {
    late OpenCodeProvider provider;
    late _FakeOpenCodeClient fakeClient;

    setUp(() {
      fakeClient = _FakeOpenCodeClient();
      fakeClient.eventController = StreamController<ChatEvent>.broadcast();
      provider = OpenCodeProvider(client: fakeClient, sessionId: 'sess-1');
    });

    tearDown(() async {
      await fakeClient.eventController?.close();
      provider.dispose();
    });

    test('tool calls attach to the streaming message before end of turn',
        () async {
      // Listen so the SSE pipeline starts (generateStream is lazy).
      final sub = provider.sendMessageStream('go').listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // A tool starts mid-stream — historically this stayed orphaned and only
      // surfaced after the end-of-turn loadHistory rebuild.
      fakeClient.eventController!.add(const ToolCallInputStartedEvent(
        callId: 'call-x',
        toolName: 'bash',
        sessionId: 'sess-1',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // The streaming assistant message now carries the tool, live.
      final mid = provider.getMessageIdAt(provider.history.length - 1);
      expect(mid, isNotNull);
      final tools = provider.getToolCallsForMessage(mid!);
      expect(tools.map((t) => t.name), contains('bash'),
          reason: 'tool should render during streaming, not only at the end');

      // Don't await: cancelling the mapped async* stream can stay pending
      // until the underlying SSE controller closes (handled in tearDown).
      unawaited(sub.cancel());
    });
  });

  group('OpenCodeProvider scope guard', () {
    late OpenCodeProvider provider;
    late _FakeOpenCodeClient fakeClient;

    setUp(() {
      fakeClient = _FakeOpenCodeClient();
      provider = OpenCodeProvider(client: fakeClient, sessionId: 'sess-1');
    });

    tearDown(() {
      provider.dispose();
    });

    test('in-flight loadHistory does not clobber a newly selected session',
        () async {
      final gate = Completer<void>();
      fakeClient.getSessionMessagesGate = gate;
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'id': 'msg-old', 'role': 'user'},
          'parts': [
            {'type': 'text', 'text': 'old session message'},
          ],
        },
      ];

      // Fetch for sess-1 suspends on the gate...
      final inFlight = provider.loadHistory();

      // ...and the user switches to sess-2 meanwhile.
      provider.setSession('sess-2', history: [
        ChatMessage.user('new session message', const []),
      ]);

      // The old fetch completes late: it must be discarded.
      fakeClient.getSessionMessagesGate = null;
      gate.complete();
      await inFlight;

      expect(provider.currentSessionId, 'sess-2');
      expect(provider.history.length, 1);
      expect(provider.history.first.text, 'new session message');
    });

    test('loadHistory without interleaving still applies normally', () async {
      fakeClient.getSessionMessagesResult = [
        {
          'info': {'id': 'msg-1', 'role': 'user'},
          'parts': [
            {'type': 'text', 'text': 'hello'},
          ],
        },
      ];

      await provider.loadHistory();

      expect(provider.history.length, 1);
      expect(provider.history.first.text, 'hello');
    });
  });
}
