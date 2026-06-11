import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_errors.dart';
import '../services/opencode_client.dart';

/// Modelo de sessão do OpenCode
class Session {
  final String id;
  final String slug;
  final String? title;
  final String? directory;
  final DateTime? created;
  final DateTime? updated;
  final int? inputTokens;
  final int? outputTokens;

  Session({
    required this.id,
    required this.slug,
    this.title,
    this.directory,
    this.created,
    this.updated,
    this.inputTokens,
    this.outputTokens,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    // O JSON do servidor tem time no nível raiz, não dentro de info
    final time = json['time'] as Map<String, dynamic>?;
    final tokens = json['tokens'] as Map<String, dynamic>?;

    DateTime? parseTimestamp(dynamic value) {
      if (value == null) return null;
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      } else if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      } else if (value is String) {
        try {
          return DateTime.fromMillisecondsSinceEpoch(int.parse(value));
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    return Session(
      id: json['id'] ?? '',
      slug: json['slug'] ?? '',
      title: json['title'],
      directory: json['directory'],
      created: parseTimestamp(time?['created']),
      updated: parseTimestamp(time?['updated']),
      inputTokens: tokens?['input'],
      outputTokens: tokens?['output'],
    );
  }

  String get displayName => title ?? slug;
}

/// Provider que gerencia sessões do OpenCode
class SessionProvider extends ChangeNotifier {
  static const _legacyActiveSessionKey = 'active_session_id';
  static const _activeSessionKeyPrefix = 'active_session_id_v2_';

  List<Session> _sessions = [];
  String? _currentSessionId;
  String? _activeSessionStorageKey;
  bool _isLoading = false;
  String? _error;
  OpenCodeClient? _sharedClient;

  List<Session> get sessions => _sessions;
  String? get currentSessionId => _currentSessionId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Injects a shared client from ClientProvider.
  set sharedClient(OpenCodeClient? client) => _sharedClient = client;

  static String activeSessionStorageKey({
    String? machineId,
    String? directory,
  }) {
    if (machineId == null && directory == null) {
      return _legacyActiveSessionKey;
    }
    final scope = '${machineId ?? ''}\n${directory ?? ''}';
    return '$_activeSessionKeyPrefix${base64Url.encode(utf8.encode(scope))}';
  }

  String _storageKeyFor({String? machineId, String? directory}) {
    if (machineId == null && directory == null) {
      return _activeSessionStorageKey ?? _legacyActiveSessionKey;
    }
    return activeSessionStorageKey(machineId: machineId, directory: directory);
  }

  /// Restores the selected session ID for a machine + directory scope.
  Future<void> loadPersistedSession({
    String? machineId,
    String? directory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _activeSessionStorageKey =
        activeSessionStorageKey(machineId: machineId, directory: directory);
    final sessionId = prefs.getString(_activeSessionStorageKey!);
    _currentSessionId =
        sessionId == null || sessionId.isEmpty ? null : sessionId;
    notifyListeners();
  }

  Future<void> _persistCurrentSession(
    String? sessionId, {
    String? machineId,
    String? directory,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _storageKeyFor(machineId: machineId, directory: directory);
    _activeSessionStorageKey = key;
    if (sessionId == null || sessionId.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, sessionId);
  }

  OpenCodeClient? get _client => _sharedClient;

  /// Carrega lista de sessões do servidor
  Future<void> loadSessions({String? directory}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = _client;
      if (client == null) {
        _error = 'Server not configured';
        _isLoading = false;
        notifyListeners();
        return;
      }

      final response = await client.listSessions(directory: directory);
      _sessions = response
          .whereType<Map<String, dynamic>>()
          .map((json) => Session.fromJson(json))
          .toList();

      // Ordena por updated mais recente (descendente)
      _sessions.sort((a, b) {
        if (a.updated == null && b.updated == null) return 0;
        if (a.updated == null) return 1;
        if (b.updated == null) return -1;
        return b.updated!.compareTo(a.updated!);
      });
    } catch (e) {
      _error = 'Failed to load sessions: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Bijective session rule: a restored session may only be attached when it
  /// still exists on the server and belongs to [expectedDirectory].
  ///
  /// Returns false when the session is gone or demonstrably belongs to a
  /// different directory. Transport failures (offline, timeout) fail open so
  /// restore still works without connectivity; auth errors also fail open
  /// because they say nothing about the session itself.
  Future<bool> verifySessionScope(
    String sessionId, {
    String? expectedDirectory,
  }) async {
    final client = _client;
    if (client == null) return true;

    Map<String, dynamic> session;
    try {
      session = await client.getSession(sessionId);
    } on NotFoundError {
      return false;
    } on ApiError {
      return true;
    } catch (_) {
      return true;
    }

    // Only verify against absolute paths; relative or `~` inputs cannot be
    // compared reliably on the client side.
    if (expectedDirectory == null || !expectedDirectory.startsWith('/')) {
      return true;
    }
    final actual = session['directory'] as String?;
    if (actual == null || actual.isEmpty) return true;

    String norm(String p) =>
        p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
    return norm(actual) == norm(expectedDirectory);
  }

  /// Seleciona uma sessão como atual
  Future<void> selectSession(
    String sessionId, {
    String? machineId,
    String? directory,
  }) async {
    _currentSessionId = sessionId;
    await _persistCurrentSession(
      sessionId,
      machineId: machineId,
      directory: directory,
    );
    notifyListeners();
  }

  /// Clears the current session selection (for lazy creation).
  Future<void> clearCurrentSession({
    String? machineId,
    String? directory,
  }) async {
    _currentSessionId = null;
    await _persistCurrentSession(
      null,
      machineId: machineId,
      directory: directory,
    );
    notifyListeners();
  }

  /// Cria uma nova sessão e adiciona à lista
  Future<Session?> createSession({
    String? title,
    String? directory,
    String? machineId,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = _client;
      if (client == null) {
        _error = 'Server not configured';
        _isLoading = false;
        notifyListeners();
        return null;
      }

      final response = await client.createSession(
        title: title,
        directory: directory,
      );
      final session = Session.fromJson(response);

      _sessions.insert(0, session);
      _currentSessionId = session.id;
      await _persistCurrentSession(
        session.id,
        machineId: machineId,
        directory: session.directory ?? directory,
      );

      _isLoading = false;
      notifyListeners();
      return session;
    } catch (e) {
      _error = 'Failed to create session: $e';
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  /// Encontra uma sessão pelo ID
  Session? findSession(String sessionId) {
    try {
      return _sessions.firstWhere((s) => s.id == sessionId);
    } catch (_) {
      return null;
    }
  }

  /// Renomeia uma sessão
  Future<void> renameSession(String sessionId, String newTitle) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = _client;
      if (client == null) {
        _error = 'Server not configured';
        _isLoading = false;
        notifyListeners();
        return;
      }

      await client.updateSession(sessionId, title: newTitle);

      // Atualiza localmente
      final index = _sessions.indexWhere((s) => s.id == sessionId);
      if (index >= 0) {
        final updated = Session(
          id: _sessions[index].id,
          slug: _sessions[index].slug,
          title: newTitle,
          directory: _sessions[index].directory,
          created: _sessions[index].created,
          updated: DateTime.now(),
          inputTokens: _sessions[index].inputTokens,
          outputTokens: _sessions[index].outputTokens,
        );
        _sessions[index] = updated;
      }
    } catch (e) {
      _error = 'Failed to rename session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Deleta uma sessão
  Future<void> deleteSession(String sessionId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final client = _client;
      if (client == null) {
        _error = 'Server not configured';
        _isLoading = false;
        notifyListeners();
        return;
      }

      await client.deleteSession(sessionId);
      _sessions.removeWhere((s) => s.id == sessionId);

      if (_currentSessionId == sessionId) {
        _currentSessionId = null;
        await _persistCurrentSession(null);
      }
    } catch (e) {
      _error = 'Failed to delete session: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Limpa erro atual
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
