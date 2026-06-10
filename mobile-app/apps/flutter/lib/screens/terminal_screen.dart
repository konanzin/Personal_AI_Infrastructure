import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../services/ssh_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  SSHClient? _sshClient;
  SSHSession? _shell;
  bool _connecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _connect();
  }

  Future<void> _connect() async {
    final machine = context.read<MachineStore>().activeMachine;
    final ssh = machine?.ssh;
    if (ssh == null) {
      setState(() {
        _connecting = false;
        _error = 'SSH is not configured for this machine.';
      });
      return;
    }

    try {
      _terminal.write('Connecting to ${ssh.host}:${ssh.port}...\r\n');
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
      _sshClient = SSHClient(
        socket,
        username: ssh.username,
        identities: identities,
        onPasswordRequest: password != null ? () async => password : null,
      );
      await _sshClient!.authenticated;

      _shell = await _sshClient!.shell(
        pty: SSHPtyConfig(
          width: _terminal.viewWidth,
          height: _terminal.viewHeight,
        ),
      );

      _terminal.onOutput = (data) {
        _shell?.write(Uint8List.fromList(data.codeUnits));
      };

      _terminal.onResize = (w, h, _, __) {
        _shell?.resizeTerminal(w, h);
      };

      _shell!.stdout.listen(
        (data) => _terminal.write(String.fromCharCodes(data)),
        onDone: () {
          if (mounted) {
            _terminal.write('\r\n[Connection closed]\r\n');
          }
        },
      );

      _shell!.stderr.listen(
        (data) => _terminal.write(String.fromCharCodes(data)),
      );

      // cd to current workspace directory if set
      if (mounted) {
        final dir = context.read<OpenCodeProvider>().directory;
        if (dir != null) {
          _shell!.write(Uint8List.fromList('cd ${shellEscape(dir)}\n'.codeUnits));
        }
      }

      setState(() => _connecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Connection failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _shell?.close();
    _sshClient?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.read<MachineStore>().activeMachine?.name ?? 'Terminal'),
        actions: [
          if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() { _connecting = true; _error = null; });
                _connect();
              },
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_connecting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return TerminalView(_terminal);
  }
}
