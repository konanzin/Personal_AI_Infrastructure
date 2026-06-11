import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/client_provider.dart';
import '../providers/machine_store.dart';
import '../services/provider_auth_service.dart';
import '../services/ssh_service.dart';

class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({super.key});

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  Map<String, dynamic>? _providers;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<ClientProvider>().getProviders(forceRefresh: true);
      if (mounted) setState(() { _providers = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Failed to load providers'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final machine = context.watch<MachineStore>().activeMachine;
    final hasSsh = machine?.ssh != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Providers'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: hasSsh
          ? FloatingActionButton(
              onPressed: () => _showAddProviderDialog(context),
              child: const Icon(Icons.add),
            )
          : null,
      body: _buildBody(theme, hasSsh),
    );
  }

  Widget _buildBody(ThemeData theme, bool hasSsh) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final list = _providerList();
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_outlined, size: 64,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(128)),
            const SizedBox(height: 16),
            Text('No providers configured',
                style: theme.textTheme.titleMedium),
            if (!hasSsh) ...[
              const SizedBox(height: 8),
              Text('Configure SSH on this machine to add providers',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            0, 8, 0, 8 + MediaQuery.of(context).viewPadding.bottom),
        children: [
          if (!hasSsh)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                color: theme.colorScheme.tertiaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 20,
                          color: theme.colorScheme.onTertiaryContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Read-only. Configure SSH to edit providers.',
                          style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onTertiaryContainer),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ...list.map((p) => _ProviderTile(
                name: (p['id'] ?? p['name'] ?? '').toString(),
                data: p,
              )),
        ],
      ),
    );
  }

  /// OpenCode's `/config/providers` returns `{providers: [...], default: {}}`.
  /// Extract the provider objects defensively (older shapes may differ).
  List<Map<String, dynamic>> _providerList() {
    final raw = _providers;
    if (raw == null) return const [];
    final providers = raw['providers'];
    if (providers is List) {
      return providers.whereType<Map>().map(Map<String, dynamic>.from).toList();
    }
    // Fallback: a flat id→data map (pre-1.x shape).
    return raw.entries
        .where((e) => e.value is Map)
        .map((e) => {'id': e.key, ...Map<String, dynamic>.from(e.value as Map)})
        .toList();
  }

  // ── Add provider dialog ────────────────────────────────────────────────

  static const _knownProviders = {
    'openai': 'OpenAI',
    'anthropic': 'Anthropic',
    'google': 'Google',
    'openrouter': 'OpenRouter',
  };

  void _showAddProviderDialog(BuildContext context) {
    final providerIdCtrl = TextEditingController(text: 'openai');
    final apiKeyCtrl = TextEditingController();
    String? selectedPreset = 'openai';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isCustom = selectedPreset == null;

          return AlertDialog(
            title: const Text('Add Provider'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: selectedPreset,
                    decoration: const InputDecoration(
                      labelText: 'Provider',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ..._knownProviders.entries.map((e) =>
                          DropdownMenuItem(value: e.key, child: Text(e.value))),
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('Custom')),
                    ],
                    onChanged: (v) {
                      setDialogState(() {
                        selectedPreset = v;
                        if (v != null) providerIdCtrl.text = v;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: providerIdCtrl,
                    decoration: InputDecoration(
                      labelText: 'Provider ID',
                      hintText: isCustom ? 'my-provider' : null,
                      border: const OutlineInputBorder(),
                    ),
                    enabled: isCustom,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: apiKeyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  if (isCustom) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Custom provider base URL is not supported by this flow yet.',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final providerId = providerIdCtrl.text.trim();
                  final apiKey = apiKeyCtrl.text.trim();
                  if (providerId.isEmpty || apiKey.isEmpty) return;
                  Navigator.pop(ctx);
                  _addProviderViaSsh(providerId: providerId, apiKey: apiKey);
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── SSH write ──────────────────────────────────────────────────────────

  Future<void> _addProviderViaSsh({
    required String providerId,
    required String apiKey,
  }) async {
    final machine = context.read<MachineStore>().activeMachine;
    final ssh = machine?.ssh;
    if (ssh == null) return;

    setState(() => _loading = true);
    final sshService = SshService();
    try {
      await sshService.connect(
        host: ssh.host,
        port: ssh.port,
        username: ssh.username,
        privateKeyPem: ssh.privateKey,
        password: ssh.password,
      );

      // Read current auth.json (may not exist yet)
      String currentJson;
      try {
        currentJson = await sshService.execute('cat $providerAuthJsonPath');
      } on SshCommandException {
        currentJson = '{}';
      }

      final authData = mergeProviderAuthJson(
        currentJson: currentJson,
        providerId: providerId,
        apiKey: apiKey,
      );

      final writeCmd = buildAuthJsonWriteCommand(authData);
      await sshService.execute(writeCmd);

      if (!mounted) return;

      // Verify that OpenCode recognizes the new provider
      context.read<ClientProvider>().invalidateProviderCache();
      await _load();
      if (!mounted) return;

      final recognized =
          _providerList().any((p) => p['id'] == providerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(recognized
              ? 'Provider "$providerId" added'
              : 'Credentials saved, but OpenCode did not report '
                  '"$providerId" yet. A server restart may be required.'),
          duration: Duration(seconds: recognized ? 3 : 6),
        ));
      }
    } catch (e) {
      if (mounted) {
        final safeMsg = e is SshCommandException
            ? 'SSH command failed (exit ${e.exitCode})'
            : 'Provider update failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(safeMsg),
              backgroundColor: Theme.of(context).colorScheme.error),
        );
        setState(() => _loading = false);
      }
    } finally {
      sshService.disconnect();
    }
  }
}

// ── Provider tile ────────────────────────────────────────────────────────

class _ProviderTile extends StatelessWidget {
  final String name;
  final Map<String, dynamic> data;

  const _ProviderTile({required this.name, required this.data});

  String _sanitizeApiKey(String? key) {
    if (key == null || key.isEmpty) return '(not set)';
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final models = data['models'];
    final apiKey = data['apiKey'] as String? ?? data['key'] as String?;

    int modelCount = 0;
    if (models is List) {
      modelCount = models.length;
    } else if (models is Map) {
      modelCount = models.length;
    }

    return ExpansionTile(
      leading: Icon(Icons.extension,
          color: theme.colorScheme.primary),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text('$modelCount models  |  Key: ${_sanitizeApiKey(apiKey)}',
          style: theme.textTheme.bodySmall),
      children: [
        if (models is Map)
          ...models.entries.map((e) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: Text(e.key, style: const TextStyle(fontSize: 13)),
              )),
        if (models is List)
          ...models.map((m) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 56, right: 16),
                title: Text(m.toString(), style: const TextStyle(fontSize: 13)),
              )),
      ],
    );
  }
}
