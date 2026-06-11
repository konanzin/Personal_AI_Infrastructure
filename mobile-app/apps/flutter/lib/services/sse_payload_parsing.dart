/// Pure parsing helpers for OpenCode SSE payloads.
///
/// Extracted from `OpenCodeProvider` so the protocol surface — the part most
/// exposed to OpenCode API evolution — can be tested in isolation with
/// recorded fixtures. Everything here is a pure function of its inputs:
/// no provider state, no side effects beyond debug logging.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Normalizes an event payload (raw JSON string or decoded map) to a map.
Map<String, dynamic>? asPayloadMap(dynamic data) {
  if (data is String) {
    try {
      data = jsonDecode(data);
    } catch (_) {
      return null;
    }
  }
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return Map<String, dynamic>.from(data);
  return null;
}

/// Parses the various timestamp shapes OpenCode emits (epoch millis as
/// int/double/string, ISO-8601 string, or `{created, updated}` maps).
DateTime? parseEventTimestamp(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    return parseEventTimestamp(value['created'] ?? value['updated']);
  }
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  if (value is double) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    final asInt = int.tryParse(value);
    if (asInt != null) return DateTime.fromMillisecondsSinceEpoch(asInt);
    return DateTime.tryParse(value);
  }
  return null;
}

/// Extracts the session id from any of the nesting shapes the server uses
/// (`properties.sessionID`, `properties.info/part/message.sessionID`,
/// `properties.session.id`, or top-level `sessionID`/`sessionId`).
String? extractSessionId(dynamic data) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'];
  if (props is Map) {
    final direct = props['sessionID'];
    if (direct is String) return direct;
    final info = props['info'];
    if (info is Map && info['sessionID'] is String) {
      return info['sessionID'] as String;
    }
    final part = props['part'];
    if (part is Map && part['sessionID'] is String) {
      return part['sessionID'] as String;
    }
    final message = props['message'];
    if (message is Map && message['sessionID'] is String) {
      return message['sessionID'] as String;
    }
    final session = props['session'];
    if (session is Map && session['id'] is String) {
      return session['id'] as String;
    }
  }
  if (map['sessionID'] is String) return map['sessionID'] as String;
  if (map['sessionId'] is String) return map['sessionId'] as String;
  return null;
}

/// Extracts message info from `message.updated`-style events
/// (`properties.info`, `properties.message`, or top-level `info`).
Map<String, dynamic>? extractMessageUpdateInfo(dynamic data) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'];
  if (props is Map) {
    final info = props['info'];
    if (info is Map) return Map<String, dynamic>.from(info);
    final message = props['message'];
    if (message is Map) return Map<String, dynamic>.from(message);
  }
  final info = map['info'];
  if (info is Map) return Map<String, dynamic>.from(info);
  return null;
}

/// Extracts part info from `message.part.updated` events.
Map<String, dynamic>? extractPartInfo(dynamic data) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'] as Map?;
  final part = props?['part'] as Map?;
  if (part == null) return null;

  final result = <String, dynamic>{
    'id': part['id'],
    'type': part['type'],
    'text': part['text'],
    'messageID': part['messageID'] ?? part['messageId'],
  };
  if (part['tool'] != null) result['tool'] = part['tool'];
  if (part['callID'] != null) result['callID'] = part['callID'];
  if (part['state'] is Map) {
    result['state'] = Map<String, dynamic>.from(part['state'] as Map);
  }
  return result;
}

/// Extracts a reasoning text delta from `message.part.delta` events, but only
/// for parts already known to be reasoning parts.
String? extractReasoningDelta(dynamic data, Set<String> reasoningPartIds) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'] as Map?;
  if (props == null) return null;

  final partId = props['partID'] as String?;
  final field = props['field'] as String?;
  final delta = props['delta'];

  if (partId == null || !reasoningPartIds.contains(partId) || field != 'text') {
    return null;
  }
  if (delta is String) return delta;
  if (delta is Map) {
    final textDelta = delta['text'] as String?;
    if (textDelta != null && textDelta.isNotEmpty) return textDelta;
  }
  return null;
}

/// Extracts the owning messageID from a `message.part.delta` event.
String? extractMessageIdFromDelta(dynamic data) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'] as Map?;
  return props?['messageID'] as String?;
}

/// Extracts a visible text delta from `message.part.delta` events.
///
/// Skips the echo of the user's own message ([lastUserMessageId]) and known
/// reasoning parts. Newly seen text parts are registered into [textPartIds]
/// as a side channel for the caller's bookkeeping.
String? extractMessagePartDelta(
  dynamic data, {
  required Set<String> textPartIds,
  required Set<String> reasoningPartIds,
  String? lastUserMessageId,
}) {
  final map = asPayloadMap(data);
  if (map == null) return null;
  final props = map['properties'] as Map?;
  if (props == null) return null;

  final partId = props['partID'] as String?;
  final field = props['field'] as String?;
  final delta = props['delta'];
  final msgId = props['messageID'] as String?;

  // Ignora eco da mensagem do usuário
  if (msgId != null && msgId == lastUserMessageId) {
    debugPrint('[PAI_SSE] Ignoring user message echo delta for msgId: $msgId');
    return null;
  }

  // Ignora reasoning parts (vão pelo caminho separado)
  if (partId != null && reasoningPartIds.contains(partId)) {
    return null;
  }

  // Qualquer campo field="text" é tratado como texto visível da resposta
  if (field != 'text') return null;
  String? textDelta;
  if (delta is String) {
    textDelta = delta;
  } else if (delta is Map) {
    textDelta = delta['text'] as String?;
  }
  if (textDelta == null || textDelta.isEmpty) return null;

  if (partId != null && !textPartIds.contains(partId)) {
    textPartIds.add(partId);
    debugPrint('[PAI_SSE] Auto-registered text partId: $partId');
  }
  return textDelta;
}
