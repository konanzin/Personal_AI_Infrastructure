import 'pulse_event.dart';

/// Renderer-side coalescing (PULSE_MOBILE_PLAN.md, C3): progressive updates
/// must not become chatter. Milestones within a per-session window collapse
/// to the latest one; `attention` always passes immediately; `digest` passes
/// immediately (the service decides whether digests render at all).
///
/// Pure and clock-injected so it is unit-testable: callers pass `nowMs` and
/// drive [flushDue] from a timer.
class PulseCoalescer {
  PulseCoalescer({this.windowMs = 10000});

  final int windowMs;
  final Map<String, int> _windowStart = {};
  final Map<String, PulseEvent> _pending = {};

  /// Returns the events to render right now for this offer.
  List<PulseEvent> offer(PulseEvent event, int nowMs) {
    if (event.level != PulseLevel.milestone) return [event];

    final key = event.sessionId;
    final start = _windowStart[key];
    if (start == null || nowMs - start >= windowMs) {
      _windowStart[key] = nowMs;
      return [event];
    }
    // Inside the window: hold the LATEST milestone, drop the previous pending.
    _pending[key] = event;
    return const [];
  }

  /// Returns pending milestones whose window has expired (call periodically).
  List<PulseEvent> flushDue(int nowMs) {
    final due = <PulseEvent>[];
    for (final key in _pending.keys.toList()) {
      final start = _windowStart[key] ?? 0;
      if (nowMs - start >= windowMs) {
        due.add(_pending.remove(key)!);
        _windowStart[key] = nowMs;
      }
    }
    return due;
  }

  bool get hasPending => _pending.isNotEmpty;
}
