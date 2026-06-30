import 'dart:collection';

import 'pulse_event.dart';

/// Catch-up reconciliation (ADR-001 hard requirement #1): blackout windows
/// are a fact of life — on every (re)connect the client fetches
/// `GET /recent` and reconciles against what it already rendered, so events
/// arrive late rather than never, without replaying a backlog out loud.
class PulseReconciler {
  PulseReconciler({this.capacity = 500, Iterable<String>? initial}) {
    if (initial != null) {
      for (final key in initial) {
        _seen.add(key);
      }
      while (_seen.length > capacity) {
        _seen.remove(_seen.first);
      }
    }
  }

  final int capacity;
  final LinkedHashSet<String> _seen = LinkedHashSet();

  /// Insertion-ordered snapshot of seen keys, for persistence across restarts.
  List<String> export() => _seen.toList(growable: false);

  /// True if this delivery was not rendered before; marks it as rendered.
  bool markAndCheckFresh(String dedupeKey) {
    if (_seen.contains(dedupeKey)) return false;
    _seen.add(dedupeKey);
    while (_seen.length > capacity) {
      _seen.remove(_seen.first);
    }
    return true;
  }

  /// Filters a /recent backlog down to what deserves rendering after a
  /// reconnect: every unseen `attention`, the single latest unseen
  /// `milestone`, and the single latest unseen `digest`. Everything unseen
  /// is marked as seen regardless (skipped backlog must not resurface).
  List<PulseEvent> reconcile(List<PulseEvent> recent) {
    final fresh = <PulseEvent>[];
    for (final event in recent) {
      if (markAndCheckFresh(event.dedupeKey)) fresh.add(event);
    }
    if (fresh.isEmpty) return const [];

    final out = <PulseEvent>[
      ...fresh.where((e) => e.level == PulseLevel.attention),
    ];
    final milestones = fresh.where((e) => e.level == PulseLevel.milestone);
    if (milestones.isNotEmpty) out.add(milestones.last);
    final digests = fresh.where((e) => e.level == PulseLevel.digest);
    if (digests.isNotEmpty) out.add(digests.last);
    return out;
  }
}
