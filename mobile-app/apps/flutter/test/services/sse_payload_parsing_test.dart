import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/sse_payload_parsing.dart';

void main() {
  group('asPayloadMap', () {
    test('accepts decoded maps and JSON strings', () {
      expect(asPayloadMap({'a': 1}), {'a': 1});
      expect(asPayloadMap(jsonEncode({'a': 1})), {'a': 1});
    });

    test('returns null for non-JSON strings and non-maps', () {
      expect(asPayloadMap('not json'), isNull);
      expect(asPayloadMap(42), isNull);
      expect(asPayloadMap(null), isNull);
    });
  });

  group('parseEventTimestamp', () {
    test('parses epoch millis in int, double and string form', () {
      final expected = DateTime.fromMillisecondsSinceEpoch(1700000000000);
      expect(parseEventTimestamp(1700000000000), expected);
      expect(parseEventTimestamp(1700000000000.0), expected);
      expect(parseEventTimestamp('1700000000000'), expected);
    });

    test('parses ISO strings and {created} maps', () {
      expect(parseEventTimestamp('2026-06-10T12:00:00Z'),
          DateTime.parse('2026-06-10T12:00:00Z'));
      expect(parseEventTimestamp({'created': 1700000000000}),
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
    });

    test('returns null for garbage', () {
      expect(parseEventTimestamp('soon'), isNull);
      expect(parseEventTimestamp(null), isNull);
    });
  });

  group('extractSessionId', () {
    test('finds the id in every server nesting shape', () {
      expect(
          extractSessionId({
            'properties': {'sessionID': 's1'}
          }),
          's1');
      expect(
          extractSessionId({
            'properties': {
              'info': {'sessionID': 's2'}
            }
          }),
          's2');
      expect(
          extractSessionId({
            'properties': {
              'part': {'sessionID': 's3'}
            }
          }),
          's3');
      expect(
          extractSessionId({
            'properties': {
              'message': {'sessionID': 's4'}
            }
          }),
          's4');
      expect(
          extractSessionId({
            'properties': {
              'session': {'id': 's5'}
            }
          }),
          's5');
      expect(extractSessionId({'sessionID': 's6'}), 's6');
      expect(extractSessionId({'sessionId': 's7'}), 's7');
    });

    test('returns null when absent', () {
      expect(extractSessionId({'properties': {}}), isNull);
    });
  });

  group('extractMessageUpdateInfo', () {
    test('prefers properties.info, falls back to message and top-level', () {
      expect(
          extractMessageUpdateInfo({
            'properties': {
              'info': {'id': 'm1', 'role': 'assistant'}
            }
          }),
          {'id': 'm1', 'role': 'assistant'});
      expect(
          extractMessageUpdateInfo({
            'properties': {
              'message': {'id': 'm2'}
            }
          }),
          {'id': 'm2'});
      expect(
          extractMessageUpdateInfo({
            'info': {'id': 'm3'}
          }),
          {'id': 'm3'});
    });
  });

  group('extractPartInfo', () {
    test('extracts tool part with state', () {
      final info = extractPartInfo({
        'properties': {
          'part': {
            'id': 'p1',
            'type': 'tool',
            'messageID': 'm1',
            'tool': 'bash',
            'callID': 'c1',
            'state': {'status': 'running'},
          }
        }
      });

      expect(info!['id'], 'p1');
      expect(info['tool'], 'bash');
      expect(info['callID'], 'c1');
      expect(info['state'], {'status': 'running'});
    });

    test('normalizes messageId casing', () {
      final info = extractPartInfo({
        'properties': {
          'part': {'id': 'p1', 'type': 'text', 'messageId': 'm1'}
        }
      });
      expect(info!['messageID'], 'm1');
    });

    test('returns null without a part', () {
      expect(extractPartInfo({'properties': {}}), isNull);
    });
  });

  group('extractMessagePartDelta', () {
    Map<String, dynamic> delta({
      String partId = 'p1',
      String field = 'text',
      dynamic delta = 'hello',
      String? messageId,
    }) =>
        {
          'properties': {
            'partID': partId,
            'field': field,
            'delta': delta,
            if (messageId != null) 'messageID': messageId,
          }
        };

    test('returns text deltas and registers the part id', () {
      final textIds = <String>{};
      final result = extractMessagePartDelta(
        delta(),
        textPartIds: textIds,
        reasoningPartIds: {},
      );
      expect(result, 'hello');
      expect(textIds, contains('p1'));
    });

    test('supports nested {text: ...} delta shape', () {
      final result = extractMessagePartDelta(
        delta(delta: {'text': 'nested'}),
        textPartIds: {},
        reasoningPartIds: {},
      );
      expect(result, 'nested');
    });

    test('skips the echo of the user message', () {
      final result = extractMessagePartDelta(
        delta(messageId: 'user-msg-1'),
        textPartIds: {},
        reasoningPartIds: {},
        lastUserMessageId: 'user-msg-1',
      );
      expect(result, isNull);
    });

    test('skips known reasoning parts and non-text fields', () {
      expect(
          extractMessagePartDelta(
            delta(),
            textPartIds: {},
            reasoningPartIds: {'p1'},
          ),
          isNull);
      expect(
          extractMessagePartDelta(
            delta(field: 'metadata'),
            textPartIds: {},
            reasoningPartIds: {},
          ),
          isNull);
    });
  });

  group('extractReasoningDelta', () {
    test('only extracts for known reasoning parts with field=text', () {
      final payload = {
        'properties': {'partID': 'r1', 'field': 'text', 'delta': 'thinking...'}
      };
      expect(extractReasoningDelta(payload, {'r1'}), 'thinking...');
      expect(extractReasoningDelta(payload, {}), isNull);
    });
  });

  group('extractMessageIdFromDelta', () {
    test('reads properties.messageID', () {
      expect(
          extractMessageIdFromDelta({
            'properties': {'messageID': 'm9'}
          }),
          'm9');
      expect(extractMessageIdFromDelta({'properties': {}}), isNull);
    });
  });
}
