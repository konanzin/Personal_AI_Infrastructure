import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/client_provider.dart';

class ProviderScreen extends StatefulWidget {
  const ProviderScreen({super.key});

  @override
  State<ProviderScreen> createState() => _ProviderScreenState();
}

class _ProviderScreenState extends State<ProviderScreen> {
  Map<String, dynamic>? _providers;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final clientProvider = context.read<ClientProvider>();
      final data = await clientProvider.getProviders(forceRefresh: true);
      if (mounted) {
        setState(() {
          _providers = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  List<_ProviderInfo> _parseProviders() {
    if (_providers == null) return [];
    final result = <_ProviderInfo>[];

    final allRaw = _providers!['all'] ?? _providers!['providers'];
    final List allList;
    if (allRaw is List) {
      allList = allRaw;
    } else if (_providers!.values.any((v) => v is List)) {
      allList = _providers!.values.whereType<List>().expand((l) => l).toList();
    } else {
      allList = [];
    }

    for (final prov in allList) {
      if (prov is! Map) continue;
      final id = prov['id']?.toString() ?? prov['name']?.toString() ?? 'unknown';
      final models = <String>[];

      final provModels = prov['models'];
      if (provModels is Map) {
        models.addAll(provModels.keys.map((k) => k.toString()));
      } else if (provModels is List) {
        for (final m in provModels) {
          if (m is Map) {
            models.add(m['id']?.toString() ?? m['name']?.toString() ?? '');
          } else {
            models.add(m.toString());
          }
        }
      }

      result.add(_ProviderInfo(id: id, models: models));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Providers'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _loadProviders,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadProviders,
                  child: _buildProviderList(theme),
                ),
    );
  }

  Widget _buildProviderList(ThemeData theme) {
    final providers = _parseProviders();

    if (providers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.hub_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
            const SizedBox(height: 16),
            Text('No providers configured', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Configure providers in your OpenCode server',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Providers são configurados no servidor OpenCode via variáveis de ambiente (API keys). '
                  'Para usar um modelo, selecione-o no picker da AppBar durante o chat.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (int i = 0; i < providers.length; i++) ...[
          _ProviderCard(provider: providers[i]),
          if (i < providers.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _ProviderInfo {
  final String id;
  final List<String> models;

  _ProviderInfo({required this.id, required this.models});
}

class _ProviderCard extends StatelessWidget {
  final _ProviderInfo provider;

  const _ProviderCard({required this.provider});

  IconData _getProviderIcon(String id) {
    final lower = id.toLowerCase();
    if (lower.contains('openai') || lower.contains('gpt')) return Icons.auto_awesome;
    if (lower.contains('anthropic') || lower.contains('claude')) return Icons.psychology;
    if (lower.contains('google') || lower.contains('gemini')) return Icons.diamond;
    if (lower.contains('groq')) return Icons.bolt;
    if (lower.contains('ollama')) return Icons.computer;
    return Icons.hub;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: ExpansionTile(
        leading: Icon(_getProviderIcon(provider.id), color: theme.colorScheme.primary),
        title: Text(
          provider.id,
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          '${provider.models.length} model${provider.models.length == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          const Divider(height: 1),
          for (final model in provider.models)
            ListTile(
              dense: true,
              leading: const Icon(Icons.smart_toy_outlined, size: 18),
              title: Text(model, style: theme.textTheme.bodyMedium),
            ),
          if (provider.models.isEmpty)
            const ListTile(
              dense: true,
              title: Text('No models available', style: TextStyle(fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}
