import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/chat_event.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';

void main() {
  late OpenCodeClient client;

  setUp(() {
    client = OpenCodeClient(
      ClientConfig(
        baseUrl: 'http://localhost:4096',
        username: 'user',
        password: 'pass',
      ),
    );
  });

  test('parses tool called events with input and session id', () {
    final event = client.buildTypedEventForTest(
      'session.next.tool.called',
      jsonEncode({
        'properties': {
          'sessionID': 'session-1',
          'callID': 'call-1',
          'tool': 'bash',
          'input': {'command': 'flutter analyze'},
          'provider': {'id': 'local'},
        },
      }),
    );

    expect(event, isA<ToolCallCalledEvent>());
    final tool = event! as ToolCallCalledEvent;
    expect(tool.sessionId, 'session-1');
    expect(tool.callId, 'call-1');
    expect(tool.toolName, 'bash');
    expect(tool.input['command'], 'flutter analyze');
  });

  test('parses shell lifecycle events', () {
    final started = client.buildTypedEventForTest(
      'session.next.shell.started',
      jsonEncode({
        'properties': {
          'sessionID': 'session-1',
          'callID': 'shell-1',
          'command': 'ls -la',
        },
      }),
    );
    final ended = client.buildTypedEventForTest(
      'session.next.shell.ended',
      jsonEncode({
        'properties': {
          'sessionID': 'session-1',
          'callID': 'shell-1',
          'output': 'ok',
        },
      }),
    );

    expect(started, isA<ShellStartedEvent>());
    expect((started! as ShellStartedEvent).command, 'ls -la');
    expect(ended, isA<ShellEndedEvent>());
    expect((ended! as ShellEndedEvent).output, 'ok');
  });

  test('preserves message part payloads for provider association', () {
    final event = client.buildTypedEventForTest(
      'message.part.updated',
      jsonEncode({
        'properties': {
          'part': {
            'id': 'part-1',
            'type': 'tool',
            'messageID': 'message-1',
            'callID': 'call-1',
            'tool': 'bash',
            'state': {
              'status': 'running',
              'input': {'command': 'pwd'},
            },
          },
        },
      }),
    );

    expect(event, isA<MessageEvent>());
    final message = event! as MessageEvent;
    final part = message.payload['properties']['part'] as Map<String, dynamic>;
    expect(part['messageID'], 'message-1');
    expect(part['callID'], 'call-1');
    expect(part['state']['input']['command'], 'pwd');
  });

  test('parses question asked events', () {
    final event = client.buildTypedEventForTest(
      'question.asked',
      jsonEncode({
        'properties': {
          'id': 'question-1',
          'sessionID': 'session-1',
          'questions': [
            {
              'question': 'Proceed?',
              'header': 'Confirm',
              'options': [
                {'label': 'Yes', 'description': 'Continue'},
                {'label': 'No', 'description': 'Stop'},
              ],
            },
          ],
          'tool': {'messageID': 'message-1', 'callID': 'call-1'},
        },
      }),
    );

    expect(event, isA<QuestionAskedEvent>());
    final question = event! as QuestionAskedEvent;
    expect(question.request.id, 'question-1');
    expect(question.request.questions.single.question, 'Proceed?');
    expect(question.request.questions.single.options, hasLength(2));
    expect(question.request.tool?.messageID, 'message-1');
  });
}
