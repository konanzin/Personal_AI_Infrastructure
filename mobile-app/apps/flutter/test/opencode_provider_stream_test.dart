import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/chat_event.dart';
import 'package:pai_mobile_flutter/models/message_part.dart';
import 'package:pai_mobile_flutter/providers/opencode_provider.dart';
import 'package:pai_mobile_flutter/services/connectivity_service.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';
import 'package:pai_mobile_flutter/services/secure_storage.dart';

class _FakeOpenCodeClient extends OpenCodeClient {
  final StreamController<ChatEvent> events = StreamController<ChatEvent>.broadcast();
  var sentText = '';
  List<dynamic> sessionMessages = [];

  _FakeOpenCodeClient()
      : super(
          ClientConfig(
            baseUrl: 'http://localhost:4096',
            username: 'user',
            password: 'pass',
          ),
        );

  @override
  Stream<ChatEvent> subscribeToEvents() => events.stream;

  @override
  void unsubscribe() {}

  @override
  Future<void> sendMessage(String sessionId, String text) async {
    sentText = text;
    scheduleMicrotask(() {
      events
        ..add(
          const ToolCallInputStartedEvent(
            callId: 'tool-1',
            toolName: 'bash',
            sessionId: 'session-1',
          ),
        )
        ..add(
          const ShellStartedEvent(
            callId: 'shell-1',
            command: 'flutter analyze',
            sessionId: 'session-1',
          ),
        )
        ..add(
          const MessageEvent(
            payload: {
              'properties': {
                'info': {
                  'id': 'assistant-1',
                  'role': 'assistant',
                  'sessionID': 'session-1',
                  'time': '2026-06-08T12:00:00Z',
                },
              },
            },
            sessionId: 'session-1',
            originalEvent: 'message.updated',
          ),
        )
        ..add(
          const ToolCallSuccessEvent(
            callId: 'tool-1',
            structured: {},
            content: [
              {'type': 'text', 'text': 'analysis clean'},
            ],
            provider: {},
            sessionId: 'session-1',
          ),
        )
        ..add(
          const ShellEndedEvent(
            callId: 'shell-1',
            output: 'No issues found',
            sessionId: 'session-1',
          ),
        )
        ..add(
          const TextDeltaEvent(delta: 'Done', sessionId: 'session-1'),
        )
        ..add(
          const TextEndedEvent(sessionId: 'session-1'),
        );
    });
  }

  @override
  Future<Map<String, dynamic>> getSession(String sessionId) async => {
        'id': sessionId,
      };

  @override
  Future<List<dynamic>> getSessionMessages(String sessionId) async =>
      sessionMessages;

  @override
  Future<List<dynamic>> getSessionTodos(String sessionId) async => [];

  Future<void> close() => events.close();
}

class _FailingOpenCodeClient extends OpenCodeClient {
  _FailingOpenCodeClient()
      : super(
          ClientConfig(
            baseUrl: 'http://localhost:4096',
            username: 'user',
            password: 'pass',
          ),
        );

  @override
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    throw Exception('Network error');
  }

  @override
  Stream<ChatEvent> subscribeToEvents() => const Stream<ChatEvent>.empty();

  @override
  void unsubscribe() {}
}

void main() {
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      secureStorageChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'readAll':
            return <String, String>{};
          case 'containsKey':
            return false;
          case 'read':
          case 'write':
          case 'delete':
          case 'deleteAll':
          default:
            return null;
        }
      },
    );
    SecureStorageService.readOverride = (_) async => null;
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
    SecureStorageService.readOverride = null;
  });

  test('associates tool and shell events after local id is migrated', () async {
    final client = _FakeOpenCodeClient();
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);
    addTearDown(client.close);

    final chunks = await provider.sendMessageStream('run analyzer').toList();

    expect(client.sentText, 'run analyzer');
    expect(chunks.join(), 'Done');
    expect(provider.history.toList(), hasLength(2));

    final assistantId = provider.getMessageIdAt(1);
    expect(assistantId, 'assistant-1');

    final tools = provider.getToolCallsForMessage(assistantId!);
    expect(tools, hasLength(1));
    expect(tools.single.name, 'bash');
    expect(tools.single.state, ToolCallState.completed);
    expect(
      tools.single.content
          .whereType<ToolTextContent>()
          .map((part) => part.text)
          .join(),
      contains('analysis clean'),
    );

    final shells = provider.getShellCommandsForMessage(assistantId);
    expect(shells, hasLength(1));
    expect(shells.single.command, 'flutter analyze');
    expect(shells.single.output, 'No issues found');
  });

  test('rehydrates answered question from completed question tool history',
      () async {
    final client = _FakeOpenCodeClient();
    client.sessionMessages = [
      {
        'info': {
          'id': 'user-1',
          'role': 'user',
          'time': '2026-06-08T12:00:00Z',
        },
        'parts': [
          {'id': 'part-user-1', 'type': 'text', 'text': 'ask a question'}
        ],
      },
      {
        'info': {
          'id': 'assistant-tool-1',
          'role': 'assistant',
          'time': '2026-06-08T12:00:01Z',
        },
        'parts': [
          {
            'id': 'part-tool-1',
            'type': 'tool',
            'tool': 'question',
            'callID': 'tool-question-1',
            'state': {
              'status': 'completed',
              'input': {
                'questions': [
                  {
                    'question': 'Deseja continuar?',
                    'header': 'Continuar?',
                    'options': [
                      {'label': 'SIM', 'description': 'Sim.'},
                      {'label': 'NAO', 'description': 'Nao.'},
                    ],
                  }
                ],
              },
              'metadata': {
                'answers': [
                  ['SIM']
                ],
              },
            },
          }
        ],
      },
      {
        'info': {
          'id': 'assistant-final-1',
          'role': 'assistant',
          'time': '2026-06-08T12:00:02Z',
        },
        'parts': [
          {
            'id': 'part-final-1',
            'type': 'text',
            'text': 'QUESTION_DONE',
          }
        ],
      },
    ];
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);
    addTearDown(client.close);

    await provider.loadHistory();

    expect(provider.history.toList(), hasLength(2));
    final assistantId = provider.getMessageIdAt(1);
    expect(assistantId, 'assistant-final-1');

    final answered = provider.getAnsweredQuestionsForMessage(assistantId!);
    expect(answered, hasLength(1));
    expect(
        answered.single.request.questions.single.question, 'Deseja continuar?');
    expect(answered.single.answers, [
      ['SIM']
    ]);
  });

  test('loadHistory marks connection as online on success', () async {
    final client = _FakeOpenCodeClient();
    client.sessionMessages = [
      {
        'info': {
          'id': 'user-1',
          'role': 'user',
          'time': '2026-06-08T12:00:00Z',
        },
        'parts': [
          {'id': 'part-user-1', 'type': 'text', 'text': 'hello'}
        ],
      },
      {
        'info': {
          'id': 'assistant-1',
          'role': 'assistant',
          'time': '2026-06-08T12:00:01Z',
        },
        'parts': [
          {'id': 'part-assistant-1', 'type': 'text', 'text': 'hi'}
        ],
      },
    ];
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);
    addTearDown(client.close);

    expect(provider.connectionState, isNot(ConnectionStatus.online));

    await provider.loadHistory();

    expect(provider.connectionState, ConnectionStatus.online);
  });

  test('loadHistory does not falsely mark online on failure', () async {
    final client = _FailingOpenCodeClient();
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);

    await expectLater(provider.loadHistory(), throwsException);

    expect(provider.connectionState, isNot(ConnectionStatus.online));
  });

  test('reconnect marks connection as online on success', () async {
    final client = _FakeOpenCodeClient();
    client.sessionMessages = [
      {
        'info': {
          'id': 'user-1',
          'role': 'user',
          'time': '2026-06-08T12:00:00Z',
        },
        'parts': [
          {'id': 'part-user-1', 'type': 'text', 'text': 'hello'}
        ],
      },
      {
        'info': {
          'id': 'assistant-1',
          'role': 'assistant',
          'time': '2026-06-08T12:00:01Z',
        },
        'parts': [
          {'id': 'part-assistant-1', 'type': 'text', 'text': 'hi'}
        ],
      },
    ];
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);
    addTearDown(client.close);

    expect(provider.connectionState, isNot(ConnectionStatus.online));

    await provider.reconnect();

    expect(provider.connectionState, ConnectionStatus.online);
  });

  test('reconnect does not falsely mark online on failure', () async {
    final client = _FailingOpenCodeClient();
    final provider = OpenCodeProvider(client: client, sessionId: 'session-1');
    addTearDown(provider.dispose);

    await provider.reconnect();

    expect(provider.connectionState, isNot(ConnectionStatus.online));
  });
}
