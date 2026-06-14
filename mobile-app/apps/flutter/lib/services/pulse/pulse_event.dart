/// Pulse notifications — contract v1 (opencode/docs/NOTIFICATIONS_STREAM.md).
///
/// The broker delivers `{type: 'notification', event, render, dedupe_key}`
/// frames over SSE; `GET /recent` returns bare events (no render decision).
library;

enum PulseLevel { milestone, attention, digest }

PulseLevel pulseLevelFrom(String? raw) {
  switch (raw) {
    case 'attention':
      return PulseLevel.attention;
    case 'digest':
      return PulseLevel.digest;
    default:
      // Unknown levels degrade to milestone (additive contract evolution).
      return PulseLevel.milestone;
  }
}

class PulseEvent {
  final int v;
  final String timestamp;
  final PulseLevel level;
  final String event;
  final String sessionId;
  final String? slug;
  final String? title;
  final String speak;
  final String? language;
  final Map<String, dynamic> data;

  const PulseEvent({
    required this.v,
    required this.timestamp,
    required this.level,
    required this.event,
    required this.sessionId,
    required this.slug,
    required this.title,
    required this.speak,
    required this.language,
    required this.data,
  });

  factory PulseEvent.fromJson(Map<String, dynamic> json) => PulseEvent(
        v: (json['v'] as num?)?.toInt() ?? 1,
        timestamp: json['timestamp'] as String? ?? '',
        level: pulseLevelFrom(json['level'] as String?),
        event: json['event'] as String? ?? 'unknown',
        sessionId: json['session_id'] as String? ?? 'unknown',
        slug: json['slug'] as String?,
        title: json['title'] as String?,
        speak: (json['speak'] as String? ?? '').trim(),
        language: _readLanguage(json['language']),
        data: (json['data'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  /// Mirrors the broker's dedupeKey() so events fetched via /recent (which
  /// carry no precomputed key) reconcile against SSE deliveries.
  String get dedupeKey {
    final marker = (data['message_id'] as String?) ??
        (data['phase'] as String?) ??
        timestamp;
    return '$sessionId:$event:$marker';
  }
}

String? _readLanguage(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

class PulseDelivery {
  final PulseEvent event;

  /// Broker routing decision; null for events recovered via /recent.
  final bool? brokerSpeak;
  final String? brokerReason;
  final String dedupeKey;

  const PulseDelivery({
    required this.event,
    required this.dedupeKey,
    this.brokerSpeak,
    this.brokerReason,
  });

  factory PulseDelivery.fromFrame(Map<String, dynamic> frame) {
    final event = PulseEvent.fromJson(
        (frame['event'] as Map?)?.cast<String, dynamic>() ?? const {});
    return PulseDelivery(
      event: event,
      dedupeKey: frame['dedupe_key'] as String? ?? event.dedupeKey,
      brokerSpeak: (frame['render'] as Map?)?['speak'] as bool?,
      brokerReason: (frame['render'] as Map?)?['reason'] as String?,
    );
  }

  factory PulseDelivery.recovered(PulseEvent event) =>
      PulseDelivery(event: event, dedupeKey: event.dedupeKey);
}
