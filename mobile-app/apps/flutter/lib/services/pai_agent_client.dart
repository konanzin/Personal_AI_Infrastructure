import 'dart:convert';

import 'package:http/http.dart' as http;

import 'git_status_service.dart';

/// Client for the PAI Machine Agent HTTP API.
///
/// The agent runs on the remote machine alongside OpenCode and provides
/// richer introspection (workspace discovery, git status, system info,
/// provider management, etc.) without requiring SSH.
class PaiAgentClient {
  final String baseUrl;
  final http.Client _http;

  PaiAgentClient({required this.baseUrl, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  Future<bool> isAvailable() async {
    try {
      final resp = await _http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<String> resolvePath(String path) async {
    final resp = await _get('/resolve-path', {'path': path});
    return resp['resolved'] as String;
  }

  Future<GitStatus> getGitStatus(String directory) async {
    final resp = await _get('/git-status', {'directory': directory});
    return GitStatus(
      branch: resp['branch'] as String?,
      isDirty: resp['isDirty'] as bool? ?? false,
      changedFileCount: resp['changedFileCount'] as int? ?? 0,
    );
  }

  Future<List<String>> discoverWorkspaces() async {
    final resp = await _get('/workspaces', {});
    return (resp['workspaces'] as List<dynamic>).cast<String>();
  }

  Future<bool> isOpenCodeRunning() async {
    final resp = await _get('/opencode/status', {});
    return resp['running'] as bool? ?? false;
  }

  Future<void> startOpenCode(String directory) async {
    await _post('/opencode/start', {'directory': directory});
  }

  Future<Map<String, dynamic>> getSystemInfo() async {
    return _get('/system-info', {});
  }

  Future<void> addProvider({
    required String name,
    required String apiKey,
    String? baseUrl,
  }) async {
    await _post('/providers', {
      'name': name,
      'apiKey': apiKey,
      if (baseUrl != null) 'baseUrl': baseUrl,
    });
  }

  void close() => _http.close();

  // ── Helpers ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(
      String path, Map<String, String> query) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final resp = await _http.get(uri).timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      throw PaiAgentException(path, resp.statusCode, resp.body);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final resp = await _http
        .post(
          Uri.parse('$baseUrl$path'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw PaiAgentException(path, resp.statusCode, resp.body);
    }
    return resp.body.isNotEmpty
        ? jsonDecode(resp.body) as Map<String, dynamic>
        : {};
  }
}

class PaiAgentException implements Exception {
  final String path;
  final int statusCode;
  final String body;

  PaiAgentException(this.path, this.statusCode, this.body);

  @override
  String toString() =>
      'PaiAgentException: $path returned $statusCode: $body';
}
