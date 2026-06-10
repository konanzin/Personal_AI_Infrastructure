import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pai_mobile_flutter/models/chat_event.dart';
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
  @override
  Future<List<dynamic>> getSessionMessages(String sessionId) async {
    getSessionMessagesCallCount++;
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
  Future<Map<String, dynamic>> createSession({String? title, String? directory}) async =>
      {'id': 'sess-1'};

  @override
  void unsubscribe() {}

  @override
  Stream<ChatEvent> subscribeToEvents({String? directory}) =>
      const Stream.empty();

  Object? sendMessageError;
  int sendMessageCallCount = 0;
  @override
  Future<void> sendMessage(String sessionId, String text,
      {String? directory}) async {
    sendMessageCallCount++;
    if (sendMessageError != null) {
      throw sendMessageError!;
    }
  }

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
  });
}
