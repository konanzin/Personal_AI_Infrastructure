import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/models/chat_message.dart';

// 1x1 transparent PNG.
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

void main() {
  group('ChatMessage invariant', () {
    test('user message with text is valid', () {
      final m = ChatMessage.user('oi', const []);
      expect(m.origin, MessageOrigin.user);
      expect(m.text, 'oi');
    });

    test('user message with empty text but an attachment is valid', () {
      final m = ChatMessage.user('', [
        FileAttachment(name: 'a.png', mimeType: 'image/png', bytes: base64Decode(_png)),
      ]);
      expect(m.attachments, isNotEmpty);
    });

    test('user message with neither text nor attachment is rejected', () {
      expect(() => ChatMessage.user('', const []), throwsA(isA<AssertionError>()));
    });

    test('llm message may be empty', () {
      expect(ChatMessage.llm().text, isNull);
    });
  });

  group('attachmentFromHistoryPart', () {
    test('decodes an inline data: URI to real bytes', () {
      final att = attachmentFromHistoryPart({
        'type': 'file',
        'url': 'data:image/png;base64,$_png',
        'mime': 'image/png',
        'filename': 'pixel.png',
      });
      expect(att.name, 'pixel.png');
      expect(att.mimeType, 'image/png');
      expect(att.bytes, base64Decode(_png));
      expect(att.bytes, isNotEmpty);
    });

    test('accepts mimeType/name key aliases', () {
      final att = attachmentFromHistoryPart({
        'url': 'data:image/png;base64,$_png',
        'mimeType': 'image/png',
        'name': 'alias.png',
      });
      expect(att.name, 'alias.png');
      expect(att.mimeType, 'image/png');
    });

    test('degrades gracefully for a non-data URL (empty bytes, named chip)', () {
      final att = attachmentFromHistoryPart({
        'url': 'https://example.com/doc.pdf',
        'mime': 'application/pdf',
        'filename': 'doc.pdf',
      });
      expect(att.name, 'doc.pdf');
      expect(att.mimeType, 'application/pdf');
      expect(att.bytes, isEmpty);
    });

    test('malformed base64 does not throw, yields empty bytes', () {
      final att = attachmentFromHistoryPart({
        'url': 'data:image/png;base64,!!!not-base64!!!',
        'mime': 'image/png',
      });
      expect(att.bytes, isEmpty);
      expect(att.name, 'anexo');
    });
  });
}
