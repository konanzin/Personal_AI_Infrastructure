import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/chat_event.dart';
import 'package:pai_mobile_flutter/services/opencode_client.dart';

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
}
