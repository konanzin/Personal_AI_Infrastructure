import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const _activeSessionKey = 'active_session_id';

  List<Session> _sessions = [];
  String? _currentSessionId;
  bool _isLoading = false;
  String? _error;
  OpenCodeClient? _sharedClient;

  List<Session> get sessions => _sessions;
  String? get currentSessionId => _currentSessionId;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Injects a shared client from ClientProvider.
  set sharedClient(OpenCodeClient? client) => _sharedClient = client;

  /// Restores the last selected session ID from local cache.
  Future<void> loadPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_activeSessionKey);
    if (sessionId == null || sessionId.isEmpty) return;
    _currentSessionId = sessionId;
    notifyListeners();
  }

  Future<void> _persistCurrentSession(String? sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    if (sessionId == null || sessionId.isEmpty) {
      await prefs.remove(_activeSessionKey);
      return;
    }
    await prefs.setString(_activeSessionKey, sessionId);
  }

  OpenCodeClient? get _client => _sharedClient;

  /// Carrega lista de sessões do servidor
  Future<void> loadSessions() async {
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

      final response = await client.listSessions();
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

  /// Seleciona uma sessão como atual
  Future<void> selectSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _persistCurrentSession(sessionId);
    notifyListeners();
  }

  /// Cria uma nova sessão e adiciona à lista
  Future<Session?> createSession({String? title}) async {
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

      final response = await client.createSession(title: title);
      final session = Session.fromJson(response);
      
      _sessions.insert(0, session);
      _currentSessionId = session.id;
      await _persistCurrentSession(session.id);
      
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
