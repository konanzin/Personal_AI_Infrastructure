import 'package:flutter/material.dart';

import '../models/machine.dart';
import '../services/network_policy.dart';
import '../services/opencode_client.dart';

/// App-scoped provider that manages a single [OpenCodeClient] instance.
///
/// Rebuilds the client when credentials or timeout settings change.
/// Both [SessionProvider] and [OpenCodeProvider] share this client.
class ClientProvider extends ChangeNotifier {
  OpenCodeClient? _client;
  String? _baseUrl;
  String? _username;
  String? _password;
  int _requestTimeoutSeconds = 30;
  String? _activeMachineId;

  Map<String, dynamic>? _cachedProviders;
  DateTime? _providersCacheTime;
  static const _providersCacheDuration = Duration(minutes: 5);

  OpenCodeClient? get client => _client;
  bool get isConfigured => _client != null;

  /// Returns cached providers or fetches from server.
  Future<Map<String, dynamic>> getProviders({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedProviders != null &&
        _providersCacheTime != null &&
        DateTime.now().difference(_providersCacheTime!) < _providersCacheDuration) {
      return _cachedProviders!;
    }
    if (_client == null) return {};
    _cachedProviders = await _client!.getProviders();
    _providersCacheTime = DateTime.now();
    return _cachedProviders!;
  }

  void invalidateProviderCache() {
    _cachedProviders = null;
    _providersCacheTime = null;
  }

  /// Initializes the client from a [Machine]. Skips rebuild if nothing changed.
  void initializeFromMachine(Machine machine) {
    if (_activeMachineId == machine.id &&
        _baseUrl == machine.serverUrl &&
        _username == machine.username &&
        _password == machine.password &&
        _requestTimeoutSeconds == machine.requestTimeoutSeconds) {
      return;
    }
    if (_activeMachineId != machine.id) {
      // Cached providers belong to the previous machine.
      invalidateProviderCache();
    }
    _activeMachineId = machine.id;
    _baseUrl = machine.serverUrl;
    _username = machine.username;
    _password = machine.password;
    _requestTimeoutSeconds = machine.requestTimeoutSeconds;
    _rebuildClient();
  }

  /// Updates timeout setting and rebuilds client if needed.
  void updateTimeout(int seconds) {
    if (_requestTimeoutSeconds == seconds) return;
    _requestTimeoutSeconds = seconds;
    _rebuildClient();
  }

  void _rebuildClient() {
    // Tear down the old client before the swap so no consumer can grab a
    // stale instance between the new assignment and the old close.
    final previousClient = _client;
    _client = null;
    previousClient?.close();

    if (_baseUrl == null || _username == null || _password == null) {
      notifyListeners();
      return;
    }

    final violation =
        cleartextViolation(ClientConfig.normalizeBaseUrl(_baseUrl!));
    if (violation != null) {
      debugPrint('[PAI_CLIENT] Refusing to build client: $violation');
      notifyListeners();
      return;
    }

    _client = OpenCodeClient(
      ClientConfig(
        baseUrl: _baseUrl!,
        username: _username!,
        password: _password!,
        requestTimeoutSeconds: _requestTimeoutSeconds,
      ),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
