import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pai_mobile_flutter/services/connectivity_service.dart';

void main() {
  test('heartbeat marks online and notifies listeners', () {
    final svc = ConnectivityService();
    final states = <ConnectionStatus>[];
    svc.addListener(states.add);

    svc.heartbeat();

    expect(svc.state, ConnectionStatus.online);
    expect(states, [ConnectionStatus.online]);
    svc.dispose();
  });

  test('removeListener stops notifications', () {
    final svc = ConnectivityService();
    final states = <ConnectionStatus>[];
    void listener(ConnectionStatus s) => states.add(s);

    svc.addListener(listener);
    svc.removeListener(listener);
    svc.markError();

    expect(states, isEmpty);
    expect(svc.state, ConnectionStatus.error);
    svc.dispose();
  });

  test('startReconnect enters connecting and fires within first backoff window',
      () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      var fired = 0;

      svc.startReconnect(() => fired++);
      expect(svc.state, ConnectionStatus.connecting);

      // First retry delay is 1s with ±25% jitter: never before 750ms...
      async.elapse(const Duration(milliseconds: 700));
      expect(fired, 0);
      // ...and always by 1250ms.
      async.elapse(const Duration(milliseconds: 600));
      expect(fired, 1);
      svc.dispose();
    });
  });

  test('backoff grows on consecutive retries and resets on markOnline', () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      var fired = 0;

      // First cycle consumes retryCount 0; the timer callback increments it.
      svc.startReconnect(() => fired++);
      async.elapse(const Duration(milliseconds: 1300));
      expect(fired, 1);

      // Second cycle uses retryCount 1 → 2s ±25%: not fired at 1.4s.
      svc.startReconnect(() => fired++);
      async.elapse(const Duration(milliseconds: 1400));
      expect(fired, 1);
      async.elapse(const Duration(milliseconds: 1200));
      expect(fired, 2);

      // markOnline resets the counter: next retry is back in the 1s window.
      svc.markOnline();
      svc.startReconnect(() => fired++);
      async.elapse(const Duration(milliseconds: 1300));
      expect(fired, 3);
      svc.dispose();
    });
  });

  test('cancelReconnect prevents the pending callback', () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      var fired = 0;

      svc.startReconnect(() => fired++);
      svc.cancelReconnect();
      async.elapse(const Duration(seconds: 60));

      expect(fired, 0);
      svc.dispose();
    });
  });

  test('a new startReconnect replaces the previous pending timer', () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      var first = 0;
      var second = 0;

      svc.startReconnect(() => first++);
      svc.startReconnect(() => second++);
      async.elapse(const Duration(seconds: 60));

      expect(first, 0);
      expect(second, 1);
      svc.dispose();
    });
  });

  test('dispose clears listeners and timers', () {
    fakeAsync((async) {
      final svc = ConnectivityService();
      var notifications = 0;
      var reconnects = 0;
      svc.addListener((_) => notifications++);
      svc.startReconnect(() => reconnects++);
      final notificationsBeforeDispose = notifications; // connecting state

      svc.dispose();
      async.elapse(const Duration(seconds: 60));

      expect(reconnects, 0, reason: 'pending retry timer must be cancelled');
      expect(notifications, notificationsBeforeDispose,
          reason: 'no notifications after dispose');
    });
  });
}
