import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/pulse/pulse_coalescer.dart';
import 'package:pai_mobile_flutter/services/pulse/pulse_event.dart';
import 'package:pai_mobile_flutter/services/pulse/pulse_reconciler.dart';

PulseEvent ev({
  String event = 'phase_transition',
  String level = 'milestone',
  String session = 's1',
  String speak = 'spoken line',
  String timestamp = '2026-06-11T20:00:00.000Z',
  Map<String, dynamic> data = const {},
}) =>
    PulseEvent.fromJson({
      'v': 1,
      'timestamp': timestamp,
      'level': level,
      'event': event,
      'session_id': session,
      'slug': null,
      'title': null,
      'speak': speak,
      'data': data,
    });

void main() {
  group('PulseEvent', () {
    test('dedupeKey mirrors the broker (message_id > phase > timestamp)', () {
      expect(ev(data: {'message_id': 'm1'}).dedupeKey, 's1:phase_transition:m1');
      expect(ev(data: {'phase': 'verify'}).dedupeKey, 's1:phase_transition:verify');
      expect(ev().dedupeKey, 's1:phase_transition:2026-06-11T20:00:00.000Z');
    });

    test('unknown level degrades to milestone', () {
      expect(ev(level: 'brand-new-level').level, PulseLevel.milestone);
    });

    test('delivery frame parses broker render decision', () {
      final d = PulseDelivery.fromFrame({
        'event': {'event': 'guard_denied', 'level': 'attention', 'session_id': 's1', 'speak': 'x'},
        'render': {'speak': false, 'reason': 'session-on-screen'},
        'dedupe_key': 'k1',
      });
      expect(d.brokerSpeak, false);
      expect(d.brokerReason, 'session-on-screen');
      expect(d.dedupeKey, 'k1');
    });
  });

  group('PulseReconciler', () {
    test('same dedupe key renders once', () {
      final r = PulseReconciler();
      expect(r.markAndCheckFresh('k1'), true);
      expect(r.markAndCheckFresh('k1'), false);
    });

    test('catch-up keeps every attention but only the latest milestone/digest', () {
      final r = PulseReconciler();
      final out = r.reconcile([
        ev(data: {'phase': 'plan'}),
        ev(data: {'phase': 'build'}),
        ev(level: 'attention', event: 'guard_denied', data: {'message_id': 'a1'}),
        ev(level: 'attention', event: 'security_blocked', data: {'message_id': 'a2'}),
        ev(data: {'phase': 'verify'}),
        ev(level: 'digest', event: 'session_completed', data: {'message_id': 'd1'}),
      ]);
      expect(out.map((e) => e.level).where((l) => l == PulseLevel.attention).length, 2);
      expect(out.where((e) => e.level == PulseLevel.milestone).single.data['phase'], 'verify');
      expect(out.where((e) => e.level == PulseLevel.digest).length, 1);
    });

    test('skipped backlog never resurfaces on the next reconcile', () {
      final r = PulseReconciler();
      r.reconcile([ev(data: {'phase': 'plan'}), ev(data: {'phase': 'build'})]);
      // 'plan' was skipped (only latest spoken) but must count as seen:
      expect(r.reconcile([ev(data: {'phase': 'plan'})]), isEmpty);
    });

    test('capacity bound evicts oldest keys', () {
      final r = PulseReconciler(capacity: 2);
      r.markAndCheckFresh('a');
      r.markAndCheckFresh('b');
      r.markAndCheckFresh('c'); // evicts 'a'
      expect(r.markAndCheckFresh('a'), true);
    });
  });

  group('PulseCoalescer', () {
    test('first milestone speaks, burst collapses to the latest', () {
      final c = PulseCoalescer(windowMs: 10000);
      expect(c.offer(ev(speak: 'one'), 0).single.speak, 'one');
      expect(c.offer(ev(speak: 'two'), 2000), isEmpty);
      expect(c.offer(ev(speak: 'three'), 4000), isEmpty);
      expect(c.flushDue(9000), isEmpty);
      final due = c.flushDue(10000);
      expect(due.single.speak, 'three');
    });

    test('attention bypasses the window', () {
      final c = PulseCoalescer(windowMs: 10000);
      c.offer(ev(speak: 'one'), 0);
      final out = c.offer(ev(level: 'attention', speak: 'blocked!'), 1000);
      expect(out.single.speak, 'blocked!');
    });

    test('windows are per session', () {
      final c = PulseCoalescer(windowMs: 10000);
      expect(c.offer(ev(session: 'a'), 0), isNotEmpty);
      expect(c.offer(ev(session: 'b'), 1000), isNotEmpty);
    });
  });
}
