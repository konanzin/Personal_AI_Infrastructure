/// Terminal transport for the terminal screen: OpenCode PTY over WebSocket
/// (runtime plane, preferred) with SSH shell as the recovery path.
///
/// Extracted from `terminal_screen.dart`; the screen owns UI concerns (blink,
/// gate prompts, error strings) and this service owns connect/reconnect,
/// cursor-resume bookkeeping and byte/frame decoding.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/machine.dart';
import 'api_errors.dart';
import 'opencode_client.dart';
import 'ssh_service.dart';

enum TerminalTransport { pty, ssh }

class TerminalConnectionService {
  TerminalConnectionService({
    required this.onOutput,
    this.onClosed,
    this.onTransportError,
  });

  /// Decoded text ready to be written to the terminal widget.
  final void Function(String text) onOutput;

  /// The active transport closed (server side or network).
  final void Function()? onClosed;

  /// The active transport errored.
  final void Function(Object error)? onTransportError;

  TerminalTransport? _transport;
  TerminalTransport? get activeTransport => _transport;

  // ── OpenCode PTY state (survives reconnects for cursor resume) ──
  OpenCodeClient? _client;
  String? _ptyId;
  String? _ptyDirectory;
  int? _cursor;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  // ── SSH recovery state ──
  SSHClient? _sshClient;
  SSHSession? _shell;

  /// Connects to an OpenCode PTY, reusing a running PTY in [directory] (or
  /// the one from a previous connect) so reopening resumes the same shell.
  /// Returns false when PTY mode is unavailable.
  Future<bool> connectPty(
    OpenCodeClient client, {
    String? directory,
    required int rows,
    required int cols,
  }) async {
    _client = client;
    _ptyDirectory ??= directory;
    final dir = _ptyDirectory;

    try {
      var ptyId = _ptyId;
      String? ticket;
      if (ptyId != null) {
        try {
          ticket = await client.getPtyConnectTicket(ptyId, directory: dir);
        } on NotFoundError {
          // The PTY died (e.g. the server restarted); discard it and fall
          // through to reuse-or-create instead of giving up on PTY mode.
          ptyId = null;
          _ptyId = null;
          _cursor = null;
        }
      }
      if (ptyId == null) {
        final existing = await client.listPtys(directory: dir);
        for (final pty in existing.whereType<Map<String, dynamic>>()) {
          if (pty['status'] == 'running' &&
              (dir == null || pty['cwd'] == dir)) {
            ptyId = pty['id'] as String?;
            break;
          }
        }
        ptyId ??= (await client.createPty(directory: dir))['id'] as String?;
        if (ptyId == null || ptyId.isEmpty) {
          throw StateError('PTY creation returned no id');
        }
        _ptyId = ptyId;
        _cursor = null;
        ticket = await client.getPtyConnectTicket(ptyId, directory: dir);
      }

      final uri = client.ptyConnectUri(
        ptyId,
        ticket: ticket!,
        cursor: _cursor,
        directory: dir,
      );
      final channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: const Duration(seconds: 10),
      );
      await channel.ready;

      _channel = channel;
      _wsSub = channel.stream.listen(
        _onPtyData,
        onDone: () {
          if (_transport == TerminalTransport.pty) onClosed?.call();
        },
        onError: (Object e) {
          if (_transport == TerminalTransport.pty) onTransportError?.call(e);
        },
      );

      unawaited(client
          .resizePty(ptyId, rows: rows, cols: cols, directory: dir)
          .catchError((_) {}));

      _transport = TerminalTransport.pty;
      return true;
    } catch (e) {
      debugPrint('[PAI_UI] OpenCode PTY connect failed: $e');
      disposeTransport();
      return false;
    }
  }

  void _onPtyData(dynamic data) {
    if (data is String) {
      // Track the output cursor so reconnects resume instead of replaying.
      _cursor = (_cursor ?? 0) + utf8.encode(data).length;
      onOutput(data);
      return;
    }
    if (data is List<int>) {
      // Binary frames starting with 0x00 carry control JSON ({"cursor": N}).
      if (data.isNotEmpty && data.first == 0) {
        try {
          final msg = jsonDecode(utf8.decode(data.sublist(1)));
          final cursor = msg is Map ? msg['cursor'] : null;
          if (cursor is int) _cursor = cursor;
        } catch (_) {}
        return;
      }
      _cursor = (_cursor ?? 0) + data.length;
      onOutput(utf8.decode(data, allowMalformed: true));
    }
  }

  /// Connects the SSH recovery shell. Throws [HostKeyMismatchException] when
  /// the pinned host key does not match, or any other error on failure.
  Future<void> connectSsh(
    SshConfig ssh, {
    String? initialDirectory,
    required int rows,
    required int cols,
  }) async {
    final socket = await SSHSocket.connect(ssh.host, ssh.port);
    final identities =
        ssh.privateKey != null && ssh.privateKey!.trim().isNotEmpty
            ? SSHKeyPair.fromPem(ssh.privateKey!)
            : const <SSHKeyPair>[];
    final password =
        ssh.password != null && ssh.password!.isNotEmpty ? ssh.password : null;
    if (identities.isEmpty && password == null) {
      throw StateError('SSH requires a private key or password.');
    }
    final pin = ssh.hostKeyFingerprint;
    String? seenFingerprint;
    _sshClient = SSHClient(
      socket,
      username: ssh.username,
      identities: identities,
      onPasswordRequest: password != null ? () async => password : null,
      onVerifyHostKey: (type, fingerprint) {
        seenFingerprint = formatHostKeyFingerprint(type, fingerprint);
        return pin == null || pin.isEmpty || seenFingerprint == pin;
      },
    );
    try {
      await _sshClient!.authenticated;
    } on SSHHostkeyError {
      if (pin != null && seenFingerprint != pin) {
        throw HostKeyMismatchException(expected: pin, actual: seenFingerprint);
      }
      rethrow;
    }

    _shell = await _sshClient!.shell(
      pty: SSHPtyConfig(width: cols, height: rows),
    );

    // Both directions must be UTF-8: the shell emits multi-byte sequences
    // (prompt glyphs, accents) and treating bytes as code units desyncs the
    // terminal grid from the server's cursor column. The streaming decoder
    // also handles sequences split across chunks.
    _shell!.stdout
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
      onOutput,
      onDone: () {
        if (_transport == TerminalTransport.ssh) onClosed?.call();
      },
    );
    _shell!.stderr
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(onOutput);

    if (initialDirectory != null) {
      _shell!.write(Uint8List.fromList(
          utf8.encode('cd ${shellEscape(initialDirectory)}\n')));
    }

    _transport = TerminalTransport.ssh;
  }

  /// Sends user keystrokes to the active transport.
  void writeInput(String data) {
    switch (_transport) {
      case TerminalTransport.pty:
        _channel?.sink.add(data);
      case TerminalTransport.ssh:
        _shell?.write(Uint8List.fromList(utf8.encode(data)));
      case null:
        break;
    }
  }

  /// Propagates a terminal resize to the active transport.
  void resize(int cols, int rows) {
    switch (_transport) {
      case TerminalTransport.pty:
        final ptyId = _ptyId;
        final client = _client;
        if (ptyId != null && client != null) {
          unawaited(client
              .resizePty(ptyId, rows: rows, cols: cols, directory: _ptyDirectory)
              .catchError((_) {}));
        }
      case TerminalTransport.ssh:
        _shell?.resizeTerminal(cols, rows);
      case null:
        break;
    }
  }

  /// Ends the server-side PTY session entirely (power-off action).
  Future<void> deletePtySession() async {
    final ptyId = _ptyId;
    final client = _client;
    disposeTransport();
    if (ptyId != null && client != null) {
      try {
        await client.deletePty(ptyId, directory: _ptyDirectory);
      } catch (_) {}
    }
    _ptyId = null;
    _cursor = null;
  }

  /// Tears down local transports only. The server-side PTY stays alive so it
  /// can be resumed later.
  void disposeTransport() {
    _transport = null;
    _wsSub?.cancel();
    _wsSub = null;
    _channel?.sink.close();
    _channel = null;
    _shell?.close();
    _shell = null;
    _sshClient?.close();
    _sshClient = null;
  }
}
