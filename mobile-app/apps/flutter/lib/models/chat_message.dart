import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Origin of a chat message.
///
/// These types started as the `flutter_ai_toolkit` interface types; they were
/// inlined when the toolkit dependency was removed (the app uses its own chat
/// UI, so only the data types were needed).
enum MessageOrigin {
  user,
  llm;

  bool get isUser => this == MessageOrigin.user;
  bool get isLlm => this == MessageOrigin.llm;
}

/// A file or media item attached to a chat message.
@immutable
sealed class Attachment {
  const Attachment({required this.name});

  final String name;
}

/// A file attachment with raw bytes and a MIME type.
@immutable
final class FileAttachment extends Attachment {
  const FileAttachment({
    required super.name,
    required this.mimeType,
    required this.bytes,
  });

  final String mimeType;
  final Uint8List bytes;

  @override
  String toString() =>
      'FileAttachment(name: $name, mimeType: $mimeType, '
      'bytes: ${bytes.length} bytes)';
}

/// A message in a chat conversation.
///
/// LLM messages start empty and grow via [append] as the response streams in.
class ChatMessage {
  ChatMessage({
    required this.origin,
    required this.text,
    required this.attachments,
  }) : assert(
          origin.isLlm ||
              (text != null && text.isNotEmpty) ||
              attachments.isNotEmpty,
          'A user message must carry text or at least one attachment',
        );

  factory ChatMessage.llm() =>
      ChatMessage(origin: MessageOrigin.llm, text: null, attachments: []);

  factory ChatMessage.user(String text, Iterable<Attachment> attachments) =>
      ChatMessage(
        origin: MessageOrigin.user,
        text: text,
        attachments: attachments,
      );

  String? text;

  final MessageOrigin origin;

  final Iterable<Attachment> attachments;

  void append(String text) => this.text = (this.text ?? '') + text;

  @override
  String toString() =>
      'ChatMessage(origin: $origin, text: $text, attachments: $attachments)';
}

/// Rebuilds a [FileAttachment] from an OpenCode `file` message part as stored
/// in session history (mirrors the send shape `{type,url,mime,filename}`).
///
/// Inline `data:` URIs are decoded to real bytes so images render exactly like
/// the live conversation. A non-`data:` URL (remote/path) or a malformed
/// payload degrades to a named chip with empty bytes — the attachment tile's
/// `errorBuilder` falls back to a file/image icon, never a crash.
FileAttachment attachmentFromHistoryPart(Map part) {
  final url = part['url'] as String?;
  final mimeType =
      (part['mime'] ?? part['mimeType']) as String? ?? 'application/octet-stream';
  final name = (part['filename'] ?? part['name']) as String? ?? 'anexo';

  var bytes = Uint8List(0);
  if (url != null && url.startsWith('data:')) {
    final comma = url.indexOf(',');
    final header = comma == -1 ? '' : url.substring(5, comma);
    if (comma != -1 && header.contains('base64')) {
      try {
        bytes = base64Decode(url.substring(comma + 1));
      } catch (_) {
        // Malformed base64 — keep empty; the chip falls back to an icon.
      }
    }
  }

  return FileAttachment(name: name, mimeType: mimeType, bytes: bytes);
}
