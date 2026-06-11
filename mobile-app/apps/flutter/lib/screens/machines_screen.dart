import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/machine.dart';
import '../providers/machine_store.dart';
import '../theme.dart';
import '../services/machine_bootstrap_service.dart';
import '../services/network_policy.dart';
import '../services/opencode_client.dart';
import '../services/ssh_key_service.dart';
import '../services/ssh_service.dart';

class MachinesScreen extends StatelessWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Machines')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, null),
        child: const Icon(Icons.add),
      ),
      body: Consumer<MachineStore>(
        builder: (context, store, _) {
          if (store.machines.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 64,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withAlpha(128)),
                  const SizedBox(height: 16),
                  Text('No machines configured',
                      style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: store.machines.length,
            itemBuilder: (context, index) {
              final machine = store.machines[index];
              final isActive = machine.id == store.activeMachineId;
              return _MachineTile(
                machine: machine,
                isActive: isActive,
                onTap: () => store.switchMachine(machine.id),
                onEdit: () => _openEditor(context, machine),
                onDelete: () => _confirmDelete(context, store, machine),
              );
            },
          );
        },
      ),
    );
  }

  void _openEditor(BuildContext context, Machine? machine) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MachineEditorScreen(machine: machine),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, MachineStore store, Machine machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Delete machine?'),
        content: Text('"${machine.name}" and its settings will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await store.deleteMachine(machine.id);
    }
  }
}

class _MachineTile extends StatelessWidget {
  final Machine machine;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MachineTile({
    required this.machine,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive
            ? theme.colorScheme.primary
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.dns,
            color: isActive
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
            size: 20),
      ),
      title: Text(machine.name,
          style: TextStyle(
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal)),
      subtitle:
          Text(machine.serverUrl, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isActive)
            Icon(Icons.check_circle,
                color: theme.colorScheme.primary, size: 20),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _MachineEditorScreen extends StatefulWidget {
  final Machine? machine;
  const _MachineEditorScreen({this.machine});

  @override
  State<_MachineEditorScreen> createState() => _MachineEditorScreenState();
}

class _MachineEditorScreenState extends State<_MachineEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _timeoutCtrl;
  late final TextEditingController _defaultDirCtrl;
  // SSH
  late final TextEditingController _sshHostCtrl;
  late final TextEditingController _sshPortCtrl;
  late final TextEditingController _sshUserCtrl;
  late final TextEditingController _sshKeyCtrl;
  late final TextEditingController _sshPasswordCtrl;

  /// Host key fingerprint captured on the last successful SSH connection in
  /// this editor session. Saving stores it as the pinned fingerprint.
  String? _capturedHostKeyFingerprint;

  /// Private key PEM provisioned during this editor session (generated on
  /// device, public half installed on the server). When set, the saved
  /// SshConfig carries this key and the bootstrap password is discarded.
  String? _provisionedPrivateKey;

  bool _obscurePassword = true;
  bool _obscureSshPassword = true;
  bool _testing = false;
  bool _testingSsh = false;
  bool _saving = false;
  bool _sshExpanded = false;

  bool get _isEditing => widget.machine != null;
  bool get _busy => _testing || _testingSsh || _saving;

  @override
  void initState() {
    super.initState();
    final m = widget.machine;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _urlCtrl = TextEditingController(text: m?.serverUrl ?? '');
    _userCtrl = TextEditingController(text: m?.username ?? 'opencode');
    _passCtrl = TextEditingController(text: m?.password ?? '');
    _timeoutCtrl =
        TextEditingController(text: '${m?.requestTimeoutSeconds ?? 30}');
    _defaultDirCtrl = TextEditingController(text: m?.defaultDirectory ?? '');
    _sshHostCtrl = TextEditingController(text: m?.ssh?.host ?? '');
    _sshPortCtrl = TextEditingController(text: '${m?.ssh?.port ?? 22}');
    _sshUserCtrl = TextEditingController(text: m?.ssh?.username ?? '');
    _sshKeyCtrl = TextEditingController(text: m?.ssh?.privateKey ?? '');
    _sshPasswordCtrl = TextEditingController(text: m?.ssh?.password ?? '');
    _sshExpanded = m == null || m.ssh != null;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _timeoutCtrl.dispose();
    _defaultDirCtrl.dispose();
    _sshHostCtrl.dispose();
    _sshPortCtrl.dispose();
    _sshUserCtrl.dispose();
    _sshKeyCtrl.dispose();
    _sshPasswordCtrl.dispose();
    super.dispose();
  }

  /// Blocks plain HTTP to non-private hosts. Returns true when allowed.
  bool _cleartextGuard() {
    final violation = cleartextViolation(_effectiveServerUrl());
    if (violation == null) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(violation),
          backgroundColor: Theme.of(context).colorScheme.error),
    );
    return false;
  }

  Future<void> _testConnection() async {
    _applyDerivedServerUrlIfNeeded();
    if (!_cleartextGuard()) return;
    setState(() => _testing = true);
    try {
      final config = ClientConfig(
        baseUrl: _urlCtrl.text.trim(),
        username: _userCtrl.text.trim(),
        password: _passCtrl.text,
        requestTimeoutSeconds: int.tryParse(_timeoutCtrl.text) ?? 30,
      );
      final client = OpenCodeClient(config);
      final result = await client.checkConnection().whenComplete(client.close);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.success ? 'Connected!' : result.message),
        backgroundColor: result.success
            ? Theme.of(context).semanticColors.success
            : Theme.of(context).colorScheme.error,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error: $e'),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  String _effectiveServerUrl() {
    final raw = _urlCtrl.text.trim();
    if (raw.isNotEmpty) return ClientConfig.normalizeBaseUrl(raw);
    final sshHost = _sshHostCtrl.text.trim();
    if (sshHost.isEmpty) return '';
    return 'http://$sshHost:4096';
  }

  int _effectiveOpenCodePort() {
    final url = _effectiveServerUrl();
    final uri = Uri.tryParse(url);
    if (uri != null && uri.hasPort) return uri.port;
    return 4096;
  }

  void _applyDerivedServerUrlIfNeeded() {
    if (_urlCtrl.text.trim().isNotEmpty) return;
    final sshHost = _sshHostCtrl.text.trim();
    if (sshHost.isEmpty) return;
    _urlCtrl.text = 'http://$sshHost:4096';
  }

  String _effectiveOpenCodeUsername() {
    final username = _userCtrl.text.trim();
    return username.isNotEmpty ? username : 'opencode';
  }

  /// Returns the configured server password, generating a random one when
  /// the field is empty so machines never fall back to a guessable default.
  String _effectiveOpenCodePassword() {
    if (_passCtrl.text.isEmpty) {
      final rng = Random.secure();
      final bytes = List<int>.generate(18, (_) => rng.nextInt(256));
      _passCtrl.text = base64UrlEncode(bytes).replaceAll('=', '');
    }
    return _passCtrl.text;
  }

  Future<ConnectionCheckResult> _checkOpenCodeHttp() async {
    final client = OpenCodeClient(ClientConfig(
      baseUrl: _effectiveServerUrl(),
      username: _effectiveOpenCodeUsername(),
      password: _effectiveOpenCodePassword(),
      requestTimeoutSeconds: int.tryParse(_timeoutCtrl.text) ?? 30,
    ));
    return client.checkConnection().whenComplete(client.close);
  }

  /// Builds the config used to *connect* during setup. May include the
  /// password, because the first connection (before a key exists) needs it.
  SshConfig? _buildSshConfig() {
    final host = _sshHostCtrl.text.trim();
    final user = _sshUserCtrl.text.trim();
    final pastedKey = _sshKeyCtrl.text.trim();
    final key = pastedKey.isNotEmpty
        ? pastedKey
        : (_provisionedPrivateKey ?? widget.machine?.ssh?.privateKey);
    final password = _sshPasswordCtrl.text;
    if (host.isEmpty || user.isEmpty) return null;
    if ((key == null || key.isEmpty) && password.isEmpty) return null;
    return SshConfig(
      host: host,
      port: int.tryParse(_sshPortCtrl.text) ?? 22,
      username: user,
      privateKey: key != null && key.isNotEmpty ? key : null,
      password: password.isNotEmpty ? password : null,
      hostKeyFingerprint:
          _capturedHostKeyFingerprint ?? widget.machine?.ssh?.hostKeyFingerprint,
    );
  }

  /// Builds the config to *persist*. Once a key exists, the password is
  /// dropped so a long-term server credential is never stored on the device.
  SshConfig? _buildSshConfigForSave() {
    final base = _buildSshConfig();
    if (base == null) return null;
    if (base.privateKey != null && base.privateKey!.isNotEmpty) {
      return base.copyWith(password: null);
    }
    return base;
  }

  /// Generates a dedicated key on-device and installs its public half on the
  /// server over the (already authenticated) [ssh] connection. No-op if a key
  /// is already in play (pasted by the user or provisioned earlier).
  Future<void> _ensureKeyProvisioned(SshService ssh) async {
    if (_provisionedPrivateKey != null) return;
    if (_sshKeyCtrl.text.trim().isNotEmpty) return;
    if (widget.machine?.ssh?.privateKey != null) return;
    final name = _nameCtrl.text.trim();
    final generated = SshKeyService().generateEd25519(
      comment: 'pai-mobile-${name.isEmpty ? 'device' : name}',
    );
    await ssh.execute(installAuthorizedKeyCommand(generated.authorizedKeysLine));
    _provisionedPrivateKey = generated.privateKeyPem;
  }

  Future<void> _testSshConnection() async {
    final sshConfig = _buildSshConfig();
    if (sshConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Fill SSH host, username, and password or private key'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _testingSsh = true);
    final ssh = SshService();
    try {
      await ssh.connect(
        host: sshConfig.host,
        port: sshConfig.port,
        username: sshConfig.username,
        privateKeyPem: sshConfig.privateKey,
        password: sshConfig.password,
      );
      _capturedHostKeyFingerprint = ssh.hostKeyFingerprint;
      final whoami = await ssh.execute('whoami');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('SSH connected as $whoami'),
          backgroundColor: Theme.of(context).semanticColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('SSH connection failed'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      ssh.disconnect();
      if (mounted) setState(() => _testingSsh = false);
    }
  }

  String _bootstrapStepLabel(BootstrapStepEvent event) {
    switch (event.step) {
      case BootstrapStep.connecting:
        return 'Connecting over SSH...';
      case BootstrapStep.provisioningKey:
        return 'Generating and installing a dedicated SSH key...';
      case BootstrapStep.locatingOpenCode:
        return 'Locating opencode on the remote machine...';
      case BootstrapStep.installingController:
        return 'Installing the pai-opencode controller...';
      case BootstrapStep.startingService:
        return 'Starting the OpenCode service...';
      case BootstrapStep.waitingForHttp:
        return 'Waiting for HTTP, attempt '
            '${event.attempt}/${event.maxAttempts}...';
    }
  }

  Future<bool> _bootstrapOpenCodeViaSsh({bool showSnackBar = true}) async {
    final sshConfig = _buildSshConfig();
    if (sshConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Fill SSH host, username, and password or private key'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }

    _applyDerivedServerUrlIfNeeded();
    final serverPassword = _effectiveOpenCodePassword();
    if (_passCtrl.text.isEmpty) _passCtrl.text = serverPassword;

    setState(() => _testingSsh = true);

    final progress = ValueNotifier<String>('Connecting over SSH...');
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Setting up OpenCode'),
          content: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: progress,
                  builder: (_, value, __) => Text(value),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false));

    final name = _nameCtrl.text.trim();
    final defaultDir = _defaultDirCtrl.text.trim();
    BootstrapOutcome? outcome;
    try {
      await for (final event in MachineBootstrapService().bootstrap(
        ssh: sshConfig,
        serverUrl: _effectiveServerUrl(),
        serverUsername: _effectiveOpenCodeUsername(),
        serverPassword: serverPassword,
        port: _effectiveOpenCodePort(),
        workdir: defaultDir.isNotEmpty ? defaultDir : null,
        keyComment: 'pai-mobile-${name.isEmpty ? 'device' : name}',
        requestTimeoutSeconds: int.tryParse(_timeoutCtrl.text) ?? 30,
      )) {
        switch (event) {
          case BootstrapStepEvent e:
            progress.value = _bootstrapStepLabel(e);
          case BootstrapDoneEvent e:
            outcome = e.outcome;
        }
      }
    } finally {
      if (dialogOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      progress.dispose();
      if (mounted) setState(() => _testingSsh = false);
    }

    final result = outcome;
    if (result == null || !mounted) return false;

    if (result.hostKeyFingerprint != null) {
      _capturedHostKeyFingerprint = result.hostKeyFingerprint;
    }
    if (result.provisionedPrivateKeyPem != null) {
      _provisionedPrivateKey = result.provisionedPrivateKeyPem;
    }

    final String message;
    final Color color;
    switch (result.failure) {
      case null:
        message = result.success
            ? 'OpenCode is running and reachable'
            : 'OpenCode started, but HTTP check failed: ${result.message}';
        color = result.success
            ? Theme.of(context).semanticColors.success
            : Theme.of(context).semanticColors.warning;
      case BootstrapFailureKind.openCodeMissing:
        message = 'opencode is not installed on the remote machine';
        color = Theme.of(context).colorScheme.error;
      case BootstrapFailureKind.remoteCommandFailed:
        message = result.exitCode != null
            ? 'Remote setup failed (exit ${result.exitCode})'
            : 'SSH bootstrap failed';
        color = Theme.of(context).colorScheme.error;
      case BootstrapFailureKind.sshConnectFailed:
        message = 'SSH bootstrap failed';
        color = Theme.of(context).colorScheme.error;
    }
    if (showSnackBar || !result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color,
          duration: const Duration(seconds: 5),
        ),
      );
    }
    return result.success;
  }

  /// When SSH is configured with only a password (no key yet), opens a short
  /// connection to provision a dedicated key. Best-effort: failure here does
  /// not block saving (the password path still works as a fallback).
  Future<void> _provisionKeyIfPasswordOnly() async {
    final cfg = _buildSshConfig();
    if (cfg == null) return;
    if (cfg.privateKey != null && cfg.privateKey!.isNotEmpty) return;
    if (cfg.password == null || cfg.password!.isEmpty) return;
    final ssh = SshService();
    try {
      await ssh.connect(
        host: cfg.host,
        port: cfg.port,
        username: cfg.username,
        password: cfg.password,
        expectedHostKeyFingerprint: cfg.hostKeyFingerprint,
      );
      _capturedHostKeyFingerprint = ssh.hostKeyFingerprint;
      await _ensureKeyProvisioned(ssh);
    } catch (_) {
      // Leave the password path in place if provisioning fails.
    } finally {
      ssh.disconnect();
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final store = context.read<MachineStore>();
    _applyDerivedServerUrlIfNeeded();
    if (!_cleartextGuard()) return;
    if (_passCtrl.text.isEmpty) _passCtrl.text = _effectiveOpenCodePassword();

    setState(() => _saving = true);
    try {
      final directCheck = await _checkOpenCodeHttp();
      if (!directCheck.success) {
        final sshConfig = _buildSshConfig();
        if (sshConfig == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(directCheck.message),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
          return;
        }

        final bootstrapped =
            await _bootstrapOpenCodeViaSsh(showSnackBar: false);
        if (!bootstrapped) return;
      } else {
        // OpenCode is already reachable, so no bootstrap ran — but if SSH was
        // given with only a password, provision a key now so we never persist
        // the password.
        await _provisionKeyIfPasswordOnly();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    final defaultDir = _defaultDirCtrl.text.trim();
    // Prefer a stable identity derived from the host key over a timestamp,
    // so the same machine maps to the same ID across reinstalls.
    final newMachineId = _capturedHostKeyFingerprint != null
        ? stableMachineId(_capturedHostKeyFingerprint!)
        : DateTime.now().millisecondsSinceEpoch.toString();
    final machine = Machine(
      id: widget.machine?.id ?? newMachineId,
      name: _nameCtrl.text.trim(),
      serverUrl: _effectiveServerUrl(),
      username: _effectiveOpenCodeUsername(),
      password: _effectiveOpenCodePassword(),
      requestTimeoutSeconds: int.tryParse(_timeoutCtrl.text) ?? 30,
      defaultDirectory: defaultDir.isNotEmpty ? defaultDir : null,
      ssh: _buildSshConfigForSave(),
      lastConnected: widget.machine?.lastConnected,
    );

    if (_isEditing) {
      await store.updateActiveMachine(machine);
    } else {
      await store.addMachine(machine);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Machine' : 'Add Machine'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: Text(_saving ? 'Starting...' : 'Save & Start'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewPadding.bottom),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'My VPS',
                  prefixIcon: Icon(Icons.label_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _defaultDirCtrl,
                decoration: const InputDecoration(
                  labelText: 'Default Directory',
                  hintText: '/home/user',
                  helperText: 'Home directory on the server',
                  prefixIcon: Icon(Icons.folder_outlined),
                  border: OutlineInputBorder(),
                ),
              ),

              // ── SSH ──
              const SizedBox(height: 24),
              ExpansionTile(
                initiallyExpanded: _sshExpanded,
                onExpansionChanged: (v) => _sshExpanded = v,
                tilePadding: EdgeInsets.zero,
                title: const Text('SSH Setup'),
                subtitle: const Text(
                    'Primary path: connect, start OpenCode, then chat'),
                leading: const Icon(Icons.terminal),
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _sshHostCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSH Host',
                      hintText: '100.x.x.x or hostname',
                      prefixIcon: Icon(Icons.dns_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sshPortCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSH Port',
                      prefixIcon: Icon(Icons.numbers),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sshUserCtrl,
                    decoration: const InputDecoration(
                      labelText: 'SSH Username',
                      prefixIcon: Icon(Icons.person_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sshKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Private Key (PEM)',
                      helperText:
                          'Paste the full PEM content, or use password below',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    minLines: 2,
                    style:
                        const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _sshPasswordCtrl,
                    decoration: InputDecoration(
                      labelText: 'SSH Password',
                      helperText:
                          'Optional fallback for normal SSH password auth',
                      prefixIcon: const Icon(Icons.password_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSshPassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(
                            () => _obscureSshPassword = !_obscureSshPassword),
                      ),
                    ),
                    obscureText: _obscureSshPassword,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testSshConnection,
                    icon: _testingSsh
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.terminal),
                    label: const Text('Test SSH'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _bootstrapOpenCodeViaSsh,
                    icon: _testingSsh
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('Setup/OpenCode via SSH'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),

              const SizedBox(height: 16),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Direct OpenCode Server (optional)'),
                subtitle: const Text('Use only if OpenCode is already running'),
                leading: const Icon(Icons.link),
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OpenCode Server URL',
                      hintText: 'Auto-derived from SSH host if blank',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (value.isEmpty &&
                          _sshHostCtrl.text.trim().isNotEmpty) {
                        return null;
                      }
                      if (value.isEmpty) {
                        return 'Required unless SSH host is set';
                      }
                      if (!value.startsWith('http')) {
                        return 'Must start with http:// or https://';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _userCtrl,
                    decoration: const InputDecoration(
                      labelText: 'OpenCode Username',
                      helperText: 'Defaults to opencode',
                      prefixIcon: Icon(Icons.person_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passCtrl,
                    decoration: InputDecoration(
                      labelText: 'OpenCode Server Password',
                      helperText:
                          'Leave empty to generate a random password on setup',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _timeoutCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Timeout (seconds)',
                      prefixIcon: Icon(Icons.timer_outlined),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n < 5 || n > 300) return '5-300';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _testConnection,
                    icon: _testing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check),
                    label: const Text('Test Direct Server'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),

            ],
          ),
        ),
      ),
    );
  }
}
