/// Pulse listener — production background service (Phase C3).
///
/// Foreground service holding an identified SSE subscription to the Pulse
/// Broker, per ADR-001:
///  - catch-up via GET /recent + dedupe on EVERY (re)connect (events arrive
///    late, never never);
///  - reconnect with backoff (3s -> 60s) — blackout loops must not burn
///    battery;
///  - presence reported to the broker (focused session / foreground state)
///    so routing can stay silent while you are watching the session.
///
/// Voice: SpeechEngine (platform TTS) speaks live `event.speak` verbatim
/// while the app is foregrounded, coalesced per session. Settings (enabled,
/// per-level toggles)
/// travel via FlutterForegroundTask.saveData and live updates over
/// sendDataToTask.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'pulse_coalescer.dart';
import 'pulse_event.dart';
import 'pulse_reconciler.dart';
import 'speech_engine.dart';

// Config keys (FlutterForegroundTask.saveData — read by the task isolate)
const kPulseBrokerUrlKey = 'pulse.brokerUrl';
const kPulseEnabledKey = 'pulse.enabled';
const kPulseSpeakMilestoneKey = 'pulse.speak.milestone';
const kPulseSpeakAttentionKey = 'pulse.speak.attention';
const kPulseSpeakDigestKey = 'pulse.speak.digest';
const kPulseAppForegroundedKey = 'pulse.app.foregrounded';
// Persisted dedupe ledger (JSON array of seen keys) so a foreground-service
// restart does not re-notify a backlog. Voice is already protected by the
// live-only rule; this closes the double-NOTIFY gap.
const kPulseSeenKeysKey = 'pulse.seen';

@pragma('vm:entry-point')
void pulseListenerStartCallback() {
  FlutterForegroundTask.setTaskHandler(PulseListenerTaskHandler());
}

class PulseListenerTaskHandler extends TaskHandler {
  HttpClient? _client;
  StreamSubscription<String>? _sub;
  Timer? _flushTimer;
  bool _stopping = false;

  String _brokerUrl = '';
  String? _subscriberId;
  String? _focusedSession;
  bool _appForegrounded = false;

  bool _speakMilestone = true;
  bool _speakAttention = true;
  bool _speakDigest = true;

  late PulseReconciler _reconciler;
  bool _seenDirty = false;
  final _coalescer = PulseCoalescer();
  SpeechEngine? _speech;

  static const _backoffSeconds = [3, 5, 10, 30, 60];
  int _backoffIndex = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _brokerUrl =
        await FlutterForegroundTask.getData<String>(key: kPulseBrokerUrlKey) ??
            '';
    _speakMilestone = await FlutterForegroundTask.getData<bool>(
            key: kPulseSpeakMilestoneKey) ??
        true;
    _speakAttention = await FlutterForegroundTask.getData<bool>(
            key: kPulseSpeakAttentionKey) ??
        true;
    _speakDigest =
        await FlutterForegroundTask.getData<bool>(key: kPulseSpeakDigestKey) ??
            true;
    _appForegrounded = await FlutterForegroundTask.getData<bool>(
            key: kPulseAppForegroundedKey) ??
        false;
    _speech = NativeTtsEngine();

    // Restore the persisted dedupe ledger so a service restart does not replay
    // a backlog as fresh notifications.
    List<String>? seenInitial;
    final savedSeen =
        await FlutterForegroundTask.getData<String>(key: kPulseSeenKeysKey);
    if (savedSeen != null && savedSeen.isNotEmpty) {
      try {
        seenInitial = (jsonDecode(savedSeen) as List).cast<String>();
      } catch (_) {
        seenInitial = null; // corrupt → start empty
      }
    }
    _reconciler = PulseReconciler(initial: seenInitial);

    _flushTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      for (final event
          in _coalescer.flushDue(DateTime.now().millisecondsSinceEpoch)) {
        _render(event, speakHint: true);
      }
      if (_seenDirty) {
        _seenDirty = false;
        unawaited(FlutterForegroundTask.saveData(
          key: kPulseSeenKeysKey,
          value: jsonEncode(_reconciler.export()),
        ));
      }
    });

    if (_brokerUrl.isEmpty) {
      debugPrint('[pulse] no broker url configured; idle');
      return;
    }
    unawaited(_connectLoop());
  }

  Future<void> _connectLoop() async {
    while (!_stopping) {
      try {
        _client = HttpClient()
          ..idleTimeout = const Duration(days: 1)
          ..connectionTimeout = const Duration(seconds: 10);
        final uri =
            Uri.parse('$_brokerUrl/subscribe?device=phone&name=pai-mobile');
        final res = await (await _client!.getUrl(uri)).close();
        if (res.statusCode != 200) {
          throw HttpException('subscribe ${res.statusCode}');
        }
        _backoffIndex = 0;
        debugPrint('[pulse] connected to $_brokerUrl');

        var buffer = '';
        final done = Completer<void>();
        _sub = res.transform(utf8.decoder).listen(
          (chunk) {
            buffer += chunk;
            int sep;
            while ((sep = buffer.indexOf('\n\n')) != -1) {
              final frame = buffer.substring(0, sep);
              buffer = buffer.substring(sep + 2);
              final dataLine = frame
                  .split('\n')
                  .where((l) => l.startsWith('data: '))
                  .firstOrNull;
              if (dataLine != null) _onFrame(dataLine.substring(6));
            }
          },
          onDone: () => done.complete(),
          onError: (Object e) => done.complete(),
          cancelOnError: true,
        );
        await done.future;
        debugPrint('[pulse] stream closed');
      } catch (e) {
        debugPrint('[pulse] connect failed: $e');
      }
      if (_stopping) break;
      final delay =
          _backoffSeconds[_backoffIndex.clamp(0, _backoffSeconds.length - 1)];
      if (_backoffIndex < _backoffSeconds.length - 1) _backoffIndex++;
      await Future<void>.delayed(Duration(seconds: delay));
    }
  }

  Future<void> _onFrame(String json) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(json) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (payload['type'] == 'hello') {
      _subscriberId = payload['id'] as String?;
      debugPrint('[pulse] subscribed as $_subscriberId');
      await _pushPresence();
      await _catchUp();
      return;
    }

    if (payload['type'] != 'notification') return;
    final delivery = PulseDelivery.fromFrame(payload);
    if (!_reconciler.markAndCheckFresh(delivery.dedupeKey)) return;
    _seenDirty = true;
    for (final event in _coalescer.offer(
        delivery.event, DateTime.now().millisecondsSinceEpoch)) {
      _render(event, speakHint: delivery.brokerSpeak ?? true);
    }
  }

  /// ADR-001 #1: fetch the backlog on every (re)connect and update local
  /// notification/dedupe state. Recovered events never speak; voice is live-only.
  Future<void> _catchUp() async {
    try {
      final uri = Uri.parse('$_brokerUrl/recent?n=50');
      final res = await (await _client!.getUrl(uri)).close();
      final body = await res.transform(utf8.decoder).join();
      final events = ((jsonDecode(body) as Map)['events'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PulseEvent.fromJson(e.cast<String, dynamic>()))
          .toList();
      final fresh = _reconciler.reconcile(events);
      if (events.isNotEmpty) _seenDirty = true; // reconcile marks unseen as seen
      for (final event in fresh) {
        _render(
          event,
          speakHint: false,
          recovered: true,
        );
      }
    } catch (e) {
      debugPrint('[pulse] catch-up failed: $e');
    }
  }

  void _render(PulseEvent event,
      {required bool speakHint, bool recovered = false}) {
    final levelEnabled = switch (event.level) {
      PulseLevel.milestone => _speakMilestone,
      PulseLevel.attention => _speakAttention,
      PulseLevel.digest => _speakDigest,
    };

    // Local focus guard mirrors the broker: never speak the session on screen.
    final watchingIt = _appForegrounded &&
        _focusedSession != null &&
        (_focusedSession == event.sessionId || _focusedSession == event.slug);

    final speak = !recovered &&
        _appForegrounded &&
        speakHint &&
        levelEnabled &&
        !watchingIt;

    FlutterForegroundTask.updateService(
      notificationTitle: event.title ?? 'PAI',
      notificationText: event.speak.isNotEmpty ? event.speak : event.event,
    );
    final language = normalizePulseTtsLanguage(event.language);
    if (speak && event.speak.isNotEmpty && language != null) {
      unawaited(_speech?.speak(
        event.speak,
        language: language,
      ));
    }
  }

  Future<void> _pushPresence() async {
    if (_subscriberId == null || _brokerUrl.isEmpty) return;
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final req = await client.postUrl(Uri.parse('$_brokerUrl/presence'));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'id': _subscriberId,
        'focusedSession': _appForegrounded ? _focusedSession : null,
        'listening': true,
      }));
      await (await req.close()).drain<void>();
      client.close();
    } catch (e) {
      debugPrint('[pulse] presence push failed: $e');
    }
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final map = data.cast<String, dynamic>();
    switch (map['type']) {
      case 'presence':
        _focusedSession = map['focusedSession'] as String?;
        _appForegrounded = map['foregrounded'] as bool? ?? false;
        unawaited(_pushPresence());
      case 'settings':
        _speakMilestone = map['milestone'] as bool? ?? _speakMilestone;
        _speakAttention = map['attention'] as bool? ?? _speakAttention;
        _speakDigest = map['digest'] as bool? ?? _speakDigest;
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _stopping = true;
    _flushTimer?.cancel();
    if (_seenDirty) {
      _seenDirty = false;
      await FlutterForegroundTask.saveData(
        key: kPulseSeenKeysKey,
        value: jsonEncode(_reconciler.export()),
      );
    }
    await _sub?.cancel();
    _client?.close(force: true);
    await _speech?.stop();
  }
}

/// App-side coordinator: the active machine and the user toggle both feed
/// here; whichever changes last wins. Kept static because the two writers
/// (provider graph and settings) have no natural shared ancestor.
class PulseRuntime {
  static String? serverUrl;
  static bool enabled = false;

  static Future<void> sync() async {
    final broker = serverUrl != null
        ? PulseServiceController.brokerUrlFromServerUrl(serverUrl!)
        : null;
    if (enabled && broker != null) {
      await PulseServiceController.start(brokerUrl: broker);
    } else {
      await PulseServiceController.stop();
    }
  }
}

/// UI-side controller: owns service lifecycle and forwards presence/settings.
class PulseServiceController {
  static const int _serviceId = 991;

  static Future<void> ensureConfigured() async {
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'pai_pulse',
        channelName: 'PAI Pulse',
        channelDescription: 'Narração de progresso do PAI',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Derives the broker URL from the machine's server URL host (port 31337).
  static String? brokerUrlFromServerUrl(String serverUrl) {
    try {
      final uri = Uri.parse(serverUrl);
      if (uri.host.isEmpty) return null;
      return 'http://${uri.host}:31337';
    } catch (_) {
      return null;
    }
  }

  static Future<void> start({required String brokerUrl}) async {
    await ensureConfigured();
    await FlutterForegroundTask.saveData(
        key: kPulseBrokerUrlKey, value: brokerUrl);
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.restartService();
      return;
    }
    await FlutterForegroundTask.startService(
      serviceId: _serviceId,
      notificationTitle: 'PAI Pulse',
      notificationText: 'Conectado ao broker',
      callback: pulseListenerStartCallback,
    );
  }

  static Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  static void pushPresence(
      {String? focusedSession, required bool foregrounded}) {
    unawaited(FlutterForegroundTask.saveData(
        key: kPulseAppForegroundedKey, value: foregrounded));
    FlutterForegroundTask.sendDataToTask({
      'type': 'presence',
      'focusedSession': focusedSession,
      'foregrounded': foregrounded,
    });
  }

  static void pushSettings({bool? milestone, bool? attention, bool? digest}) {
    FlutterForegroundTask.sendDataToTask({
      'type': 'settings',
      if (milestone != null) 'milestone': milestone,
      if (attention != null) 'attention': attention,
      if (digest != null) 'digest': digest,
    });
  }
}
