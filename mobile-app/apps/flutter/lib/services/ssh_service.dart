import 'package:dartssh2/dartssh2.dart';

class SshService {
  SSHClient? _client;

  bool get isConnected => _client != null;

  Future<void> connect({
    required String host,
    int port = 22,
    required String username,
    String? privateKeyPem,
    String? password,
  }) async {
    disconnect();
    final identities = privateKeyPem != null && privateKeyPem.trim().isNotEmpty
        ? SSHKeyPair.fromPem(privateKeyPem)
        : const <SSHKeyPair>[];
    final passwordValue =
        password != null && password.isNotEmpty ? password : null;
    if (identities.isEmpty && passwordValue == null) {
      throw StateError('SSH requires a private key or password');
    }

    final socket = await SSHSocket.connect(host, port);
    _client = SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest:
          passwordValue != null ? () async => passwordValue : null,
    );
    await _client!.authenticated;
  }

  /// Executes a command and returns its stdout. Throws on non-zero exit.
  Future<String> execute(String command) async {
    final client = _client;
    if (client == null) throw StateError('SSH not connected');

    final session = await client.execute(command);
    final stdout = StringBuffer();
    final stderr = StringBuffer();

    // Read stdout and stderr concurrently to avoid deadlock when one
    // stream's buffer fills before the other is drained.
    await Future.wait([
      session.stdout
          .forEach((chunk) => stdout.write(String.fromCharCodes(chunk))),
      session.stderr
          .forEach((chunk) => stderr.write(String.fromCharCodes(chunk))),
    ]);

    // Wait for the process to finish and provide an exit code.
    await session.done;
    final exitCode = session.exitCode;
    session.close();

    if (exitCode != null && exitCode != 0) {
      throw SshCommandException(command, exitCode, stderr.toString());
    }
    return stdout.toString().trimRight();
  }

  void disconnect() {
    _client?.close();
    _client = null;
  }
}

class SshCommandException implements Exception {
  final String command;
  final int exitCode;
  final String stderr;

  SshCommandException(this.command, this.exitCode, this.stderr);

  @override
  String toString() =>
      'SshCommandException: command=$command exit=$exitCode stderr=$stderr';
}

/// Shell-safe quoting: wraps value in single quotes, escaping embedded quotes.
String shellEscape(String s) => "'${s.replaceAll("'", r"'\''")}'";
