import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/machine.dart';
import '../l10n/app_localizations.dart';
import '../providers/machine_store.dart';
import '../theme.dart';
import '../services/classifier_config_service.dart';
import '../services/machine_bootstrap_service.dart';
import '../services/network_policy.dart';
import '../services/opencode_client.dart';
import '../services/ssh_key_service.dart';
import '../services/ssh_service.dart';

class MachinesScreen extends StatelessWidget {
  const MachinesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.machines)),
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
                  Text(l10n.noMachinesConfigured,
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(l10n.deleteMachineTitle),
        content: Text(l10n.deleteMachineBody(machine.name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(l10n.delete),
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
    final l10n = AppLocalizations.of(context)!;
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
              PopupMenuItem(value: 'edit', child: Text(l10n.editMachine)),
              PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
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
  late final TextEditingController _classifierModelCtrl;
  late bool _classifierUseLlm;
  bool _loadingClassifier = false;
  String? _classifierServerStatus;
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

  /// Durable server URL the anchor advertised (e.g. its Tailscale address),
  /// adopted as the saved URL only after we confirm this device can reach it.
  String? _resolvedAnchorUrl;

  /// Address-resolution strategy the anchor reported (`tailscale`, `lan`, ...);
  /// drives the "install Tailscale for from-anywhere reach" nudge.
  String? _anchorStrategy;

  bool _obscurePassword = true;
  bool _obscureSshPassword = true;
  bool _testing = false;
  bool _testingSsh = false;
  bool _saving = false;
  bool _allowPop = false;
  bool _sshExpanded = false;

  bool get _isEditing => widget.machine != null;
  bool get _busy => _testing || _testingSsh || _saving;

  List<TextEditingController> get _controllers => [
        _nameCtrl,
        _urlCtrl,
        _userCtrl,
        _passCtrl,
        _timeoutCtrl,
        _defaultDirCtrl,
        _classifierModelCtrl,
        _sshHostCtrl,
        _sshPortCtrl,
        _sshUserCtrl,
        _sshKeyCtrl,
        _sshPasswordCtrl,
      ];

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
    _classifierModelCtrl =
        TextEditingController(text: m?.classifierModel ?? '');
    _classifierUseLlm = m?.classifierUseLlm ?? true;
    _sshHostCtrl = TextEditingController(text: m?.ssh?.host ?? '');
    _sshPortCtrl = TextEditingController(text: '${m?.ssh?.port ?? 22}');
    _sshUserCtrl = TextEditingController(text: m?.ssh?.username ?? '');
    _sshKeyCtrl = TextEditingController(text: m?.ssh?.privateKey ?? '');
    _sshPasswordCtrl = TextEditingController(text: m?.ssh?.password ?? '');
    _sshExpanded = m == null || m.ssh != null;
    for (final controller in _controllers) {
      controller.addListener(_onEditorChanged);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.removeListener(_onEditorChanged);
    }
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _timeoutCtrl.dispose();
    _defaultDirCtrl.dispose();
    _classifierModelCtrl.dispose();
    _sshHostCtrl.dispose();
    _sshPortCtrl.dispose();
    _sshUserCtrl.dispose();
    _sshKeyCtrl.dispose();
    _sshPasswordCtrl.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    if (mounted) setState(() {});
  }

  bool get _hasUnsavedChanges {
    if (_allowPop) return false;
    final machine = widget.machine;
    if (machine == null) {
      return _nameCtrl.text.trim().isNotEmpty ||
          _urlCtrl.text.trim().isNotEmpty ||
          _passCtrl.text.isNotEmpty ||
          _defaultDirCtrl.text.trim().isNotEmpty ||
          _classifierModelCtrl.text.trim().isNotEmpty ||
          !_classifierUseLlm ||
          _sshHostCtrl.text.trim().isNotEmpty ||
          _sshUserCtrl.text.trim().isNotEmpty ||
          _sshKeyCtrl.text.trim().isNotEmpty ||
          _sshPasswordCtrl.text.isNotEmpty ||
          _userCtrl.text.trim() != 'opencode' ||
          _timeoutCtrl.text.trim() != '30' ||
          _sshPortCtrl.text.trim() != '22';
    }

    return _nameCtrl.text.trim() != machine.name ||
        _effectiveServerUrl() !=
            ClientConfig.normalizeBaseUrl(machine.serverUrl) ||
        _effectiveOpenCodeUsername() != machine.username ||
        _passCtrl.text != machine.password ||
        (int.tryParse(_timeoutCtrl.text) ?? 30) !=
            machine.requestTimeoutSeconds ||
        _defaultDirCtrl.text.trim() != (machine.defaultDirectory ?? '') ||
        _classifierModelCtrl.text.trim() != (machine.classifierModel ?? '') ||
        _classifierUseLlm != (machine.classifierUseLlm ?? true) ||
        _sshHostCtrl.text.trim() != (machine.ssh?.host ?? '') ||
        (int.tryParse(_sshPortCtrl.text) ?? 22) != (machine.ssh?.port ?? 22) ||
        _sshUserCtrl.text.trim() != (machine.ssh?.username ?? '') ||
        _sshKeyCtrl.text.trim() != (machine.ssh?.privateKey ?? '') ||
        _sshPasswordCtrl.text != (machine.ssh?.password ?? '');
  }

  Future<bool> _confirmDiscardChanges() async {
    if (!_hasUnsavedChanges) return true;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_outlined),
        title: Text(l10n.discardMachineChangesTitle),
        content: Text(l10n.discardMachineChangesBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.continueEditing),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(l10n.discard),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _popEditor() async {
    if (!mounted) return;
    setState(() => _allowPop = true);
    await Future<void>.delayed(Duration.zero);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _handleBack() async {
    if (_busy) return;
    if (await _confirmDiscardChanges()) {
      await _popEditor();
    }
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
    final l10n = AppLocalizations.of(context)!;
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
        content: Text(result.success ? l10n.connected : result.message),
        backgroundColor: result.success
            ? Theme.of(context).semanticColors.success
            : Theme.of(context).colorScheme.error,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.errorWithDetail(e.toString())),
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
    final anchor = _resolvedAnchorUrl;
    if (anchor != null && anchor.isNotEmpty) {
      return ClientConfig.normalizeBaseUrl(anchor);
    }
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
    final anchor = _resolvedAnchorUrl;
    if (anchor != null && anchor.isNotEmpty) {
      _urlCtrl.text = ClientConfig.normalizeBaseUrl(anchor);
      return;
    }
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

  /// Probes whether THIS device can reach a specific server URL (e.g. the
  /// anchor's advertised Tailscale address). Used to decide whether to adopt it
  /// as the durable saved URL — we never persist an address the phone can't hit.
  Future<bool> _probeServerUrl(String url) async {
    final client = OpenCodeClient(ClientConfig(
      baseUrl: url,
      username: _effectiveOpenCodeUsername(),
      password: _effectiveOpenCodePassword(),
      requestTimeoutSeconds: 5,
    ));
    try {
      return (await client.checkConnection()).success;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
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
      hostKeyFingerprint: _capturedHostKeyFingerprint ??
          widget.machine?.ssh?.hostKeyFingerprint,
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
    await ssh
        .execute(installAuthorizedKeyCommand(generated.authorizedKeysLine));
    _provisionedPrivateKey = generated.privateKeyPem;
  }

  Future<void> _testSshConnection() async {
    final l10n = AppLocalizations.of(context)!;
    final sshConfig = _buildSshConfig();
    if (sshConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fillSshCredentials),
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
          content: Text(l10n.sshConnectedAs(whoami)),
          backgroundColor: Theme.of(context).semanticColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.sshConnectionFailed),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      ssh.disconnect();
      if (mounted) setState(() => _testingSsh = false);
    }
  }

  String _bootstrapStepLabel(BootstrapStepEvent event) {
    final l10n = AppLocalizations.of(context)!;
    switch (event.step) {
      case BootstrapStep.connecting:
        return l10n.connectingOverSsh;
      case BootstrapStep.provisioningKey:
        return l10n.provisioningDedicatedSshKey;
      case BootstrapStep.installingPaiEcosystem:
        return l10n.installingPaiEcosystem;
      case BootstrapStep.startingPulseBroker:
        return l10n.startingPulseBroker;
      case BootstrapStep.locatingOpenCode:
        return l10n.locatingOpenCode;
      case BootstrapStep.installingController:
        return l10n.installingPaiController;
      case BootstrapStep.startingService:
        return l10n.startingOpenCodeService;
      case BootstrapStep.waitingForHttp:
        return l10n.waitingForHttpAttempt(
            event.attempt ?? 0, event.maxAttempts ?? 0);
    }
  }

  String _remoteSetupFailureMessage(BootstrapOutcome result) {
    final l10n = AppLocalizations.of(context)!;
    final base = result.exitCode != null
        ? l10n.remoteSetupFailedExit(result.exitCode!)
        : l10n.remoteSetupFailed;
    final detail = result.message
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .lastOrNull;
    if (detail == null) return base;
    final compact =
        detail.length > 180 ? '${detail.substring(0, 180)}...' : detail;
    return '$base: $compact';
  }

  Future<bool> _bootstrapOpenCodeViaSsh({bool showSnackBar = true}) async {
    final l10n = AppLocalizations.of(context)!;
    final sshConfig = _buildSshConfig();
    if (sshConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fillSshCredentials),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return false;
    }

    _applyDerivedServerUrlIfNeeded();
    final serverPassword = _effectiveOpenCodePassword();
    if (_passCtrl.text.isEmpty) _passCtrl.text = serverPassword;

    setState(() => _testingSsh = true);

    final progress = ValueNotifier<String>(l10n.connectingOverSsh);
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.settingUpOpenCode),
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
    _anchorStrategy = result.anchorStrategy;

    // Adopt the anchor's durable (e.g. Tailscale) address as the saved URL only
    // when the user did not type one AND this device can actually reach it, so a
    // saved machine never points at an address the phone cannot hit.
    if (result.success &&
        result.anchorServerUrl != null &&
        _urlCtrl.text.trim().isEmpty &&
        result.anchorServerUrl != _effectiveServerUrl() &&
        await _probeServerUrl(result.anchorServerUrl!)) {
      _resolvedAnchorUrl = result.anchorServerUrl;
    }
    if (!mounted) return false;

    final String message;
    final Color color;
    switch (result.failure) {
      case null:
        message = result.success
            ? l10n.openCodeRunningReachable
            : l10n.openCodeStartedHttpFailed(result.message);
        color = result.success
            ? Theme.of(context).semanticColors.success
            : Theme.of(context).semanticColors.warning;
      case BootstrapFailureKind.openCodeMissing:
        message = l10n.openCodeMissingRemote;
        color = Theme.of(context).colorScheme.error;
      case BootstrapFailureKind.remoteCommandFailed:
        message = _remoteSetupFailureMessage(result);
        color = Theme.of(context).colorScheme.error;
      case BootstrapFailureKind.sshConnectFailed:
        message = l10n.sshBootstrapFailed;
        color = Theme.of(context).colorScheme.error;
    }
    final showNudge = result.success &&
        (_anchorStrategy == 'lan' || _anchorStrategy == 'loopback');
    final displayMessage =
        showNudge ? '$message\n\n${l10n.anchorTailscaleHint}' : message;
    if (showSnackBar || !result.success || showNudge) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(displayMessage),
          backgroundColor: color,
          duration: Duration(seconds: showNudge ? 8 : 5),
        ),
      );
    }
    return result.success;
  }

  /// Runs `install.sh --update` on the machine over SSH (via the idempotent
  /// ecosystem command), showing progress and the result. Updates files on
  /// disk; a reconnect/restart is what loads new plugin code.
  Future<void> _updatePaiViaSsh() async {
    final l10n = AppLocalizations.of(context)!;
    final sshConfig = _buildSshConfig();
    if (sshConfig == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.fillSshCredentials),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _testingSsh = true);
    final progress = ValueNotifier<String>(l10n.connectingOverSsh);
    var dialogOpen = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(l10n.updatePaiSetup),
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

    BootstrapOutcome? outcome;
    try {
      await for (final event
          in MachineBootstrapService().updatePai(ssh: sshConfig)) {
        switch (event) {
          case BootstrapStepEvent e:
            progress.value = e.step == BootstrapStep.connecting
                ? l10n.connectingOverSsh
                : l10n.updatingPai;
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
    if (result == null || !mounted) return;
    if (result.hostKeyFingerprint != null) {
      _capturedHostKeyFingerprint = result.hostKeyFingerprint;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.success
            ? l10n.paiUpdated
            : _remoteSetupFailureMessage(result)),
        backgroundColor: result.success
            ? Theme.of(context).semanticColors.success
            : Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 6),
      ),
    );
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

  /// Opens a picker of the models actually available on the server (fetched
  /// over HTTP via the editor's current URL/credentials) and fills the model
  /// field. Free-text entry stays available as a fallback for custom models.
  Future<void> _pickClassifierModel() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_cleartextGuard()) return;
    final client = OpenCodeClient(ClientConfig(
      baseUrl: _effectiveServerUrl(),
      username: _effectiveOpenCodeUsername(),
      password: _effectiveOpenCodePassword(),
      requestTimeoutSeconds: int.tryParse(_timeoutCtrl.text) ?? 30,
    ));

    List<String> models;
    try {
      models = (await client.getProviderRegistry()).modelIds;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.couldNotLoadModels),
          backgroundColor: Theme.of(context).colorScheme.error,
        ));
      }
      return;
    } finally {
      client.close();
    }
    if (!mounted) return;

    final current = _classifierModelCtrl.text.trim();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: Text(l10n.defaultServerModel),
              selected: current.isEmpty,
              onTap: () => Navigator.pop(sheetContext, ''),
            ),
            if (models.isEmpty)
              ListTile(
                enabled: false,
                title: Text(l10n.noModelsFound),
              ),
            ...models.map((m) => ListTile(
                  leading: const Icon(Icons.psychology_outlined),
                  title: Text(m),
                  selected: m == current,
                  trailing: m == current ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(sheetContext, m),
                )),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() => _classifierModelCtrl.text = picked);
    }
  }

  /// Reads the machine's actual classifier.json over SSH and reflects it in the
  /// editor, so the app shows the real server state instead of a stale local
  /// copy. Resolves drift between device and machine on demand.
  Future<void> _loadClassifierFromServer() async {
    final l10n = AppLocalizations.of(context)!;
    final cfg = _buildSshConfig();
    if (cfg == null) {
      setState(() => _classifierServerStatus = l10n.classifierNeedsSsh);
      return;
    }

    setState(() => _loadingClassifier = true);
    final ssh = SshService();
    try {
      await ssh.connect(
        host: cfg.host,
        port: cfg.port,
        username: cfg.username,
        privateKeyPem: cfg.privateKey,
        password: cfg.password,
        expectedHostKeyFingerprint: cfg.hostKeyFingerprint,
      );
      String currentJson;
      try {
        currentJson = await ssh.execute('cat $classifierConfigPath');
      } on SshCommandException {
        currentJson = '';
      }
      final remote = parseClassifierConfigJson(currentJson);
      if (!mounted) return;
      setState(() {
        if (remote.model != null) {
          _classifierModelCtrl.text = remote.model!;
          _classifierUseLlm = remote.useLlm ?? _classifierUseLlm;
          _classifierServerStatus = l10n.classifierFromServer;
        } else {
          _classifierServerStatus = l10n.classifierNotOnServer;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _classifierServerStatus = l10n.classifierServerReadFailed);
      }
    } finally {
      ssh.disconnect();
      if (mounted) setState(() => _loadingClassifier = false);
    }
  }

  /// Pushes the per-machine classifier config to the server's
  /// classifier.json over SSH. Best-effort: a failure here surfaces a snackbar
  /// but does not block saving the machine. No-op when no model is set.
  Future<void> _pushClassifierConfigViaSsh() async {
    final model = _classifierModelCtrl.text.trim();
    if (model.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final cfg = _buildSshConfig();
    if (cfg == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.classifierNeedsSsh),
            backgroundColor: Theme.of(context).semanticColors.warning,
          ),
        );
      }
      return;
    }
    final ssh = SshService();
    try {
      await ssh.connect(
        host: cfg.host,
        port: cfg.port,
        username: cfg.username,
        privateKeyPem: cfg.privateKey,
        password: cfg.password,
        expectedHostKeyFingerprint: cfg.hostKeyFingerprint,
      );
      String currentJson;
      try {
        currentJson = await ssh.execute('cat $classifierConfigPath');
      } on SshCommandException {
        currentJson = '{}';
      }
      final data = mergeClassifierConfigJson(
        currentJson: currentJson,
        model: model,
        useLlm: _classifierUseLlm,
      );
      await ssh.execute(buildClassifierConfigWriteCommand(data));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.classifierConfigUpdated),
            backgroundColor: Theme.of(context).semanticColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.classifierConfigPushFailed),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
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
      // Push the per-machine classifier config (best-effort; no-op if unset).
      await _pushClassifierConfigViaSsh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }

    final defaultDir = _defaultDirCtrl.text.trim();
    final classifierModel = _classifierModelCtrl.text.trim();
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
      classifierModel: classifierModel.isNotEmpty ? classifierModel : null,
      classifierUseLlm: classifierModel.isNotEmpty ? _classifierUseLlm : null,
      ssh: _buildSshConfigForSave(),
      lastConnected: widget.machine?.lastConnected,
    );

    if (_isEditing) {
      await store.updateActiveMachine(machine);
    } else {
      await store.addMachine(machine);
    }
    await _popEditor();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _busy ? null : _handleBack),
          title: Text(_isEditing ? l10n.editMachine : l10n.addMachine),
          actions: [
            TextButton(
              onPressed: _busy ? null : _save,
              child: Text(_saving ? l10n.starting : l10n.saveAndStart),
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
                  decoration: InputDecoration(
                    labelText: l10n.name,
                    hintText: 'My VPS',
                    prefixIcon: const Icon(Icons.label_outlined),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? l10n.validationRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _defaultDirCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.defaultDirectory,
                    hintText: '/home/user',
                    helperText: l10n.homeDirectoryOnServer,
                    prefixIcon: const Icon(Icons.folder_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),

                // ── Prompt classifier ──
                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.classifierSetup),
                  subtitle: Text(l10n.classifierSetupSubtitle),
                  leading: const Icon(Icons.category_outlined),
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _classifierModelCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.classifierModelLabel,
                        hintText: 'openai/gpt-5.5',
                        helperText: l10n.classifierModelHelper,
                        prefixIcon: const Icon(Icons.psychology_outlined),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_drop_down),
                          tooltip: l10n.chooseModel,
                          onPressed: _busy ? null : _pickClassifierModel,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(l10n.classifierUseLlmLabel),
                      subtitle: Text(l10n.classifierUseLlmSubtitle),
                      value: _classifierUseLlm,
                      onChanged: (v) => setState(() => _classifierUseLlm = v),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: (_busy || _loadingClassifier)
                              ? null
                              : _loadClassifierFromServer,
                          icon: _loadingClassifier
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined,
                                  size: 18),
                          label: Text(l10n.loadFromServer),
                        ),
                        if (_classifierServerStatus != null)
                          Expanded(
                            child: Text(
                              _classifierServerStatus!,
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.end,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),

                // ── SSH ──
                const SizedBox(height: 24),
                ExpansionTile(
                  initiallyExpanded: _sshExpanded,
                  onExpansionChanged: (v) => _sshExpanded = v,
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.sshSetup),
                  subtitle: Text(l10n.sshSetupSubtitle),
                  leading: const Icon(Icons.terminal),
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _sshHostCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.sshHost,
                        hintText: '100.x.x.x or hostname',
                        prefixIcon: const Icon(Icons.dns_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sshPortCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.sshPort,
                        prefixIcon: const Icon(Icons.numbers),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sshUserCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.sshUsername,
                        prefixIcon: const Icon(Icons.person_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sshKeyCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.privateKeyPem,
                        helperText: l10n.privateKeyPemHelper,
                        prefixIcon: const Icon(Icons.vpn_key_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      minLines: 2,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _sshPasswordCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.sshPassword,
                        helperText: l10n.sshPasswordHelper,
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
                      label: Text(l10n.testSsh),
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
                      label: Text(l10n.setupOpenCodeViaSsh),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _updatePaiViaSsh,
                      icon: const Icon(Icons.system_update_alt),
                      label: Text(l10n.updatePaiSetup),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),

                const SizedBox(height: 16),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(l10n.directOpenCodeServer),
                  subtitle: Text(l10n.directOpenCodeServerSubtitle),
                  leading: const Icon(Icons.link),
                  children: [
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _urlCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.openCodeServerUrl,
                        hintText: l10n.openCodeServerUrlHint,
                        prefixIcon: const Icon(Icons.link),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (value.isEmpty &&
                            _sshHostCtrl.text.trim().isNotEmpty) {
                          return null;
                        }
                        if (value.isEmpty) {
                          return l10n.serverUrlRequiredUnlessSsh;
                        }
                        if (!value.startsWith('http')) {
                          return l10n.serverUrlMustStartHttp;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _userCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.openCodeUsername,
                        helperText: l10n.openCodeUsernameHelper,
                        prefixIcon: const Icon(Icons.person_outlined),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _passCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.openCodeServerPassword,
                        helperText: l10n.openCodeServerPasswordHelper,
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
                      decoration: InputDecoration(
                        labelText: l10n.timeoutSeconds,
                        prefixIcon: const Icon(Icons.timer_outlined),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 5 || n > 300) {
                          return l10n.timeoutRange;
                        }
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
                      label: Text(l10n.testDirectServer),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
