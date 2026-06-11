import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:xterm/xterm.dart';

import '../providers/client_provider.dart';
import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../services/ssh_gate_service.dart';
import '../services/ssh_service.dart';
import '../services/terminal_connection_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final Terminal _terminal;
  late final TerminalConnectionService _connection;
  bool _connecting = true;
  String? _error;

  // ── Cursor blink (xterm.dart paints a static cursor; blink is simulated
  // by toggling the theme's cursor color) ──
  final FocusNode _focusNode = FocusNode();
  Timer? _blinkTimer;
  bool _cursorVisible = true;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: 10000);
    _connection = TerminalConnectionService(
      onOutput: _terminal.write,
      onClosed: () {
        if (!mounted) return;
        _terminal.write(
            _connection.activeTransport == TerminalTransport.pty
                ? '\r\n[Connection closed — tap refresh to reconnect]\r\n'
                : '\r\n[Connection closed]\r\n');
      },
      onTransportError: (e) {
        if (mounted) _terminal.write('\r\n[Connection error: $e]\r\n');
      },
    );
    _terminal.onOutput = (data) {
      _restartBlink();
      _connection.writeInput(data);
    };
    _terminal.onResize = (w, h, _, __) => _connection.resize(w, h);
    _focusNode.addListener(_restartBlink);
    _restartBlink();
    _connect();
  }

  /// Blinks only while focused; a keystroke resets the phase so the cursor
  /// stays solid while typing, like a regular terminal.
  void _restartBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (!_cursorVisible && mounted) {
      setState(() => _cursorVisible = true);
    } else {
      _cursorVisible = true;
    }
    if (!_focusNode.hasFocus) return;
    _blinkTimer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted) return;
      setState(() => _cursorVisible = !_cursorVisible);
    });
  }

  Future<void> _connect() async {
    final client = context.read<ClientProvider>().client;
    if (client != null) {
      final directory = context.read<OpenCodeProvider>().directory ??
          context.read<MachineStore>().activeMachine?.defaultDirectory;
      final connected = await _connection.connectPty(
        client,
        directory: directory,
        rows: _terminal.viewHeight,
        cols: _terminal.viewWidth,
      );
      if (!mounted) return;
      if (connected) {
        setState(() {
          _connecting = false;
          _error = null;
        });
        return;
      }
      _terminal.write('OpenCode PTY unavailable, '
          'falling back to SSH recovery...\r\n');
    }
    await _connectSsh();
  }

  // ── SSH recovery ────────────────────────────────────────────────────────

  Future<void> _connectSsh() async {
    final store = context.read<MachineStore>();
    final machine = store.activeMachine;
    final ssh = machine?.ssh;
    if (ssh == null || machine == null) {
      setState(() {
        _connecting = false;
        _error = 'OpenCode is unreachable and SSH is not configured '
            'for this machine.';
      });
      return;
    }

    // Gate every SSH use behind the device authenticator; 3 failures wipe the
    // stored credential so a stolen phone can't be brute-forced into a shell.
    final gate = await SshGateService().authorize(machineId: machine.id);
    if (!mounted) return;
    switch (gate.outcome) {
      case SshGateOutcome.authorized:
        break;
      case SshGateOutcome.unavailable:
        setState(() {
          _connecting = false;
          _error = 'Set up a screen lock (biometric or PIN) on this device — '
              'it is required to use SSH.';
        });
        return;
      case SshGateOutcome.failed:
        setState(() {
          _connecting = false;
          _error = 'Authentication failed. '
              '${gate.attemptsRemaining} attempt(s) left before the SSH '
              'credential is erased.';
        });
        return;
      case SshGateOutcome.wiped:
        await store.clearSshConfig(machine.id);
        if (!mounted) return;
        setState(() {
          _connecting = false;
          _error = 'Too many failed attempts — the SSH credential was erased. '
              'Re-add it in the machine settings to use SSH again.';
        });
        return;
    }

    try {
      _terminal.write('Connecting to ${ssh.host}:${ssh.port} (SSH)...\r\n');
      final initialDir = context.read<OpenCodeProvider>().directory;
      await _connection.connectSsh(
        ssh,
        initialDirectory: initialDir,
        rows: _terminal.viewHeight,
        cols: _terminal.viewWidth,
      );
      if (!mounted) return;
      setState(() => _connecting = false);
    } on HostKeyMismatchException {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'SSH host key changed. If the machine was reinstalled, '
              're-run "Test SSH" in the machine settings to trust the new key.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = 'Connection failed: $e';
        });
      }
    }
  }

  Future<void> _closePtySession() async {
    await _connection.deletePtySession();
    if (mounted) Navigator.pop(context);
  }

  void _reconnect() {
    _connection.disposeTransport();
    setState(() {
      _connecting = true;
      _error = null;
    });
    _connect();
  }

  @override
  void dispose() {
    // The PTY itself stays alive server-side so it can be resumed later;
    // only the transport is torn down here.
    _blinkTimer?.cancel();
    _focusNode.removeListener(_restartBlink);
    _focusNode.dispose();
    _connection.disposeTransport();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final machineName =
        context.read<MachineStore>().activeMachine?.name ?? 'Terminal';
    final transport = _connection.activeTransport;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(machineName, overflow: TextOverflow.ellipsis)),
            if (transport == TerminalTransport.ssh) ...[
              const SizedBox(width: 8),
              Chip(
                label: const Text('SSH recovery'),
                labelStyle: const TextStyle(fontSize: 11),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    Theme.of(context).colorScheme.errorContainer,
              ),
            ],
          ],
        ),
        actions: [
          if (transport == TerminalTransport.pty)
            IconButton(
              icon: const Icon(Icons.power_settings_new),
              tooltip: 'End terminal session',
              onPressed: _closePtySession,
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reconnect',
            onPressed: _connecting ? null : _reconnect,
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
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: TerminalView(
        _terminal,
        focusNode: _focusNode,
        autofocus: true,
        // visiblePassword stops the soft keyboard from composing text
        // (predictive input); composing renders a local preview ahead of the
        // real cursor, which reads as "the cursor lags behind what I type".
        keyboardType: TextInputType.visiblePassword,
        theme: _cursorVisible ? _kTerminalTheme : _kTerminalThemeCursorOff,
        textStyle: const TerminalStyle(
          fontFamily: 'JetBrainsMonoNerdFont',
          fontSize: 13,
        ),
      ),
    );
  }
}

TerminalTheme _terminalTheme({required Color cursor}) {
  const base = TerminalThemes.defaultTheme;
  return TerminalTheme(
    cursor: cursor,
    selection: base.selection,
    foreground: base.foreground,
    background: base.background,
    black: base.black,
    white: base.white,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
  );
}

final TerminalTheme _kTerminalTheme =
    _terminalTheme(cursor: TerminalThemes.defaultTheme.cursor);
final TerminalTheme _kTerminalThemeCursorOff =
    _terminalTheme(cursor: const Color(0x00000000));
