import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Serviço de armazenamento seguro para credenciais sensíveis.
/// 
/// Usa o Android Keystore para proteger:
/// - URL do servidor
/// - Username
/// - Password
class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  static const _keyServerUrl = 'server_url';
  static const _keyUsername = 'username';
  static const _keyPassword = 'password';

  /// Salva as credenciais do servidor
  static Future<void> saveCredentials({
    required String serverUrl,
    required String username,
    required String password,
  }) async {
    await _storage.write(key: _keyServerUrl, value: serverUrl);
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  /// Carrega as credenciais do servidor
  static Future<Map<String, String?>> loadCredentials() async {
    final serverUrl = await _storage.read(key: _keyServerUrl);
    final username = await _storage.read(key: _keyUsername);
    final password = await _storage.read(key: _keyPassword);

    return {
      'serverUrl': serverUrl,
      'username': username,
      'password': password,
    };
  }

  /// Remove todas as credenciais
  static Future<void> clearCredentials() async {
    await _storage.delete(key: _keyServerUrl);
    await _storage.delete(key: _keyUsername);
    await _storage.delete(key: _keyPassword);
  }

  /// Verifica se existem credenciais salvas
  static Future<bool> hasCredentials() async {
    final credentials = await loadCredentials();
    return credentials['serverUrl'] != null &&
        credentials['username'] != null &&
        credentials['password'] != null;
  }

  /// Leitura/escrita genérica para dados auxiliares (ex: question answers).
  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  static Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
