import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pulse/pulse_listener_service.dart';

import '../services/opencode_client.dart';
import '../services/secure_storage.dart';

/// Modelo de configurações do app
class AppSettings {
  final String serverUrl;
  final String username;
  final String password;
  final bool isConfigured;
  final int requestTimeoutSeconds;

  /// Transitional: will be migrated to Machine.defaultDirectory in Phase 4.
  final String? defaultDirectory;

  const AppSettings({
    this.serverUrl = 'http://localhost:4096',
    this.username = 'opencode',
    this.password = 'pai-mobile',
    this.isConfigured = false,
    this.requestTimeoutSeconds = 30,
    this.defaultDirectory,
  });

  AppSettings copyWith({
    String? serverUrl,
    String? username,
    String? password,
    bool? isConfigured,
    int? requestTimeoutSeconds,
    String? defaultDirectory,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      isConfigured: isConfigured ?? this.isConfigured,
      requestTimeoutSeconds:
          requestTimeoutSeconds ?? this.requestTimeoutSeconds,
      defaultDirectory: defaultDirectory ?? this.defaultDirectory,
    );
  }
}

/// Provider que gerencia as configurações do app
class SettingsProvider extends ChangeNotifier {
  AppSettings _settings = const AppSettings();
  bool _isLoading = false;
  String? _error;

  AppSettings get settings => _settings;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Carrega configurações do secure storage
  Future<void> loadSettings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final credentials = await SecureStorageService.loadCredentials();
      final prefs = await SharedPreferences.getInstance();
      final timeout = prefs.getInt('request_timeout_seconds') ?? 30;
      final defaultDir = prefs.getString('default_directory');

      if (credentials['serverUrl'] != null) {
        _settings = AppSettings(
          serverUrl: credentials['serverUrl']!,
          username: credentials['username'] ?? 'opencode',
          password: credentials['password'] ?? '',
          isConfigured: true,
          requestTimeoutSeconds: timeout,
          defaultDirectory: defaultDir,
        );
      }
    } catch (e) {
      _error = 'Failed to load settings: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Salva configurações no secure storage
  Future<void> saveSettings({
    required String serverUrl,
    required String username,
    required String password,
    int? requestTimeoutSeconds,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final normalizedUrl = ClientConfig.normalizeBaseUrl(serverUrl);
      await SecureStorageService.saveCredentials(
        serverUrl: normalizedUrl,
        username: username,
        password: password,
      );

      final timeout = requestTimeoutSeconds ?? _settings.requestTimeoutSeconds;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('request_timeout_seconds', timeout);

      _settings = AppSettings(
        serverUrl: normalizedUrl,
        username: username,
        password: password,
        isConfigured: true,
        requestTimeoutSeconds: timeout,
      );
    } catch (e) {
      _error = 'Failed to save settings: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Tests the connection to the OpenCode server using real auth validation.
  ///
  /// Optionally provide unsaved [serverUrl], [username], and [password]
  /// to test credentials that have not yet been persisted.
  Future<bool> testConnection({
    String? serverUrl,
    String? username,
    String? password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final url = serverUrl ?? _settings.serverUrl;
    final user = username ?? _settings.username;
    final pass = password ?? _settings.password;

    try {
      final config = ClientConfig(
        baseUrl: url,
        username: user,
        password: pass,
      );
      final client = OpenCodeClient(config);
      final result = await client.checkConnection().whenComplete(client.close);

      if (!result.success) {
        _error = result.message;
      }

      _isLoading = false;
      notifyListeners();
      return result.success;
    } catch (e) {
      _error = 'Connection failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Saves the default directory (transitional, migrates to Machine in Phase 4).
  Future<void> saveDefaultDirectory(String? directory) async {
    final prefs = await SharedPreferences.getInstance();
    if (directory != null && directory.trim().isNotEmpty) {
      await prefs.setString('default_directory', directory.trim());
      _settings = _settings.copyWith(defaultDirectory: directory.trim());
    } else {
      await prefs.remove('default_directory');
      _settings = AppSettings(
        serverUrl: _settings.serverUrl,
        username: _settings.username,
        password: _settings.password,
        isConfigured: _settings.isConfigured,
        requestTimeoutSeconds: _settings.requestTimeoutSeconds,
      );
    }
    notifyListeners();
  }

  /// Limpa todas as configurações
  Future<void> clearSettings() async {
    await SecureStorageService.clearCredentials();
    _settings = const AppSettings();
    notifyListeners();
  }

  // ── Pulse notifications (Phase C3) ───────────────────────────────────
  bool _pulseEnabled = false;
  bool _pulseSpeakMilestone = true;
  bool _pulseSpeakAttention = true;
  bool _pulseSpeakDigest = true;

  bool get pulseEnabled => _pulseEnabled;
  bool get pulseSpeakMilestone => _pulseSpeakMilestone;
  bool get pulseSpeakAttention => _pulseSpeakAttention;
  bool get pulseSpeakDigest => _pulseSpeakDigest;

  Future<void> loadPulseSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _pulseEnabled = prefs.getBool('pulse_enabled') ?? false;
    _pulseSpeakMilestone = prefs.getBool('pulse_speak_milestone') ?? true;
    _pulseSpeakAttention = prefs.getBool('pulse_speak_attention') ?? true;
    _pulseSpeakDigest = prefs.getBool('pulse_speak_digest') ?? true;
    await _persistPulseTaskData();
    PulseRuntime.enabled = _pulseEnabled;
    await PulseRuntime.sync();
    notifyListeners();
  }

  Future<void> setPulseEnabled(bool value) async {
    _pulseEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pulse_enabled', value);
    PulseRuntime.enabled = value;
    await PulseRuntime.sync();
    notifyListeners();
  }

  Future<void> setPulseLevel(
      {bool? milestone, bool? attention, bool? digest}) async {
    final prefs = await SharedPreferences.getInstance();
    if (milestone != null) {
      _pulseSpeakMilestone = milestone;
      await prefs.setBool('pulse_speak_milestone', milestone);
    }
    if (attention != null) {
      _pulseSpeakAttention = attention;
      await prefs.setBool('pulse_speak_attention', attention);
    }
    if (digest != null) {
      _pulseSpeakDigest = digest;
      await prefs.setBool('pulse_speak_digest', digest);
    }
    await _persistPulseTaskData();
    PulseServiceController.pushSettings(
      milestone: milestone,
      attention: attention,
      digest: digest,
    );
    notifyListeners();
  }

  /// Mirrors the toggles into the task-isolate store so a restarted service
  /// boots with current values.
  Future<void> _persistPulseTaskData() async {
    await FlutterForegroundTask.saveData(
        key: kPulseSpeakMilestoneKey, value: _pulseSpeakMilestone);
    await FlutterForegroundTask.saveData(
        key: kPulseSpeakAttentionKey, value: _pulseSpeakAttention);
    await FlutterForegroundTask.saveData(
        key: kPulseSpeakDigestKey, value: _pulseSpeakDigest);
  }

  // ── Voice input ───────────────────────────────────────────────────────
  bool _voiceConfirmBeforeSend = false;
  bool get voiceConfirmBeforeSend => _voiceConfirmBeforeSend;

  Future<void> loadVoiceSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceConfirmBeforeSend =
        prefs.getBool('voice_confirm_before_send') ?? false;
    notifyListeners();
  }

  Future<void> setVoiceConfirmBeforeSend(bool value) async {
    _voiceConfirmBeforeSend = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('voice_confirm_before_send', value);
    notifyListeners();
  }

  // ── Theme ─────────────────────────────────────────────────────────────
  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('theme_mode') ?? 'system';
    _themeMode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
    notifyListeners();
  }

  // ── Theme appearance (seed / dynamic color / pure black) ──────────────
  Color? _seedColor;
  bool _useDynamicColor = false;
  bool _pureBlack = false;

  /// User-selected seed; null means the app default.
  Color? get seedColor => _seedColor;
  bool get useDynamicColor => _useDynamicColor;
  bool get pureBlack => _pureBlack;

  Future<void> loadThemeAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    final seed = prefs.getInt('theme_seed_color');
    _seedColor = seed != null ? Color(seed) : null;
    _useDynamicColor = prefs.getBool('theme_dynamic_color') ?? false;
    _pureBlack = prefs.getBool('theme_pure_black') ?? false;
    final variantName = prefs.getString('theme_scheme_variant');
    _schemeVariant = DynamicSchemeVariant.values.firstWhere(
      (v) => v.name == variantName,
      orElse: () => DynamicSchemeVariant.tonalSpot,
    );
    notifyListeners();
  }

  Future<void> setSeedColor(Color? color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    if (color != null) {
      await prefs.setInt('theme_seed_color', color.toARGB32());
    } else {
      await prefs.remove('theme_seed_color');
    }
    notifyListeners();
  }

  Future<void> setUseDynamicColor(bool value) async {
    _useDynamicColor = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_dynamic_color', value);
    notifyListeners();
  }

  Future<void> setPureBlack(bool value) async {
    _pureBlack = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('theme_pure_black', value);
    notifyListeners();
  }

  /// M3 scheme variant: how strongly the generated palette follows the seed
  /// (tonalSpot = soft default, vibrant/fidelity/expressive = stronger).
  DynamicSchemeVariant _schemeVariant = DynamicSchemeVariant.tonalSpot;
  DynamicSchemeVariant get schemeVariant => _schemeVariant;

  Future<void> setSchemeVariant(DynamicSchemeVariant variant) async {
    _schemeVariant = variant;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_scheme_variant', variant.name);
    notifyListeners();
  }

  // ── Show Thinking ────────────────────────────────────────────────────
  bool _showThinking = true;
  bool get showThinking => _showThinking;

  Future<void> loadShowThinking() async {
    final prefs = await SharedPreferences.getInstance();
    _showThinking = prefs.getBool('show_thinking') ?? true;
    notifyListeners();
  }

  Future<void> setShowThinking(bool value) async {
    _showThinking = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_thinking', value);
    notifyListeners();
  }

  // ── Display name (home-screen greeting) ───────────────────────────────
  String _displayName = '';

  /// Friendly name shown in the home greeting; empty means greet without a name.
  String get displayName => _displayName;

  Future<void> loadDisplayName() async {
    final prefs = await SharedPreferences.getInstance();
    _displayName = prefs.getString('display_name') ?? '';
    notifyListeners();
  }

  Future<void> setDisplayName(String value) async {
    _displayName = value.trim();
    final prefs = await SharedPreferences.getInstance();
    if (_displayName.isEmpty) {
      await prefs.remove('display_name');
    } else {
      await prefs.setString('display_name', _displayName);
    }
    notifyListeners();
  }
}
