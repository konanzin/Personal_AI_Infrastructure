import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/opencode_client.dart';
import '../services/secure_storage.dart';

/// Modelo de configurações do app
class AppSettings {
  final String serverUrl;
  final String username;
  final String password;
  final bool isConfigured;
  final int requestTimeoutSeconds;

  const AppSettings({
    this.serverUrl = 'http://localhost:4096',
    this.username = 'opencode',
    this.password = 'pai-mobile',
    this.isConfigured = false,
    this.requestTimeoutSeconds = 30,
  });

  AppSettings copyWith({
    String? serverUrl,
    String? username,
    String? password,
    bool? isConfigured,
    int? requestTimeoutSeconds,
  }) {
    return AppSettings(
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      isConfigured: isConfigured ?? this.isConfigured,
      requestTimeoutSeconds: requestTimeoutSeconds ?? this.requestTimeoutSeconds,
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
      
      if (credentials['serverUrl'] != null) {
        _settings = AppSettings(
          serverUrl: credentials['serverUrl']!,
          username: credentials['username'] ?? 'opencode',
          password: credentials['password'] ?? '',
          isConfigured: true,
          requestTimeoutSeconds: timeout,
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
      await SecureStorageService.saveCredentials(
        serverUrl: serverUrl,
        username: username,
        password: password,
      );

      final timeout = requestTimeoutSeconds ?? _settings.requestTimeoutSeconds;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('request_timeout_seconds', timeout);

      _settings = AppSettings(
        serverUrl: serverUrl,
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
      final success = await client.verifyAuth();

      if (!success) {
        _error = 'Authentication failed. Check URL, username, and password.';
      }

      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = 'Connection failed: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Limpa todas as configurações
  Future<void> clearSettings() async {
    await SecureStorageService.clearCredentials();
    _settings = const AppSettings();
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
}
