import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Callback for when user taps a notification (must be top-level or static).
@pragma('vm:entry-point')
void _onNotificationTap(NotificationResponse response) {
  NotificationService._pendingPayload = response.payload;
}

/// Service for local notifications when the agent needs user attention.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static String? _pendingPayload;
  static bool _initialized = false;

  static const _channelId = 'pai_agent_alerts';
  static const _channelName = 'Agent Alerts';
  static const _channelDesc = 'Notifications when the AI agent needs your attention';

  /// Returns and clears the payload from the last tapped notification.
  static String? consumePendingPayload() {
    final p = _pendingPayload;
    _pendingPayload = null;
    return p;
  }

  /// Initializes the notification plugin. Call once at app startup.
  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  /// Shows a notification that a permission is required.
  static Future<void> showPermissionNeeded({
    required String sessionId,
    String? permissionName,
  }) async {
    final body = permissionName != null
        ? 'Permission required: $permissionName'
        : 'The agent needs your permission to continue';
    await _show(
      id: sessionId.hashCode,
      title: 'PAI — Permission Required',
      body: body,
      payload: 'chat:$sessionId',
    );
  }

  /// Shows a notification that a question was asked.
  static Future<void> showQuestionAsked({
    required String sessionId,
    String? questionText,
  }) async {
    final body = questionText ?? 'The agent has a question for you';
    await _show(
      id: sessionId.hashCode + 1,
      title: 'PAI — Question',
      body: body,
      payload: 'chat:$sessionId',
    );
  }

  static Future<void> _show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
