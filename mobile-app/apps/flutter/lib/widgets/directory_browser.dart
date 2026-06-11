import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/opencode_client.dart';

/// Visual directory picker backed by OpenCode's `GET /file` listing.
///
/// Navigates the remote machine's folders over the runtime plane (no SSH).
/// Resolves with the selected absolute path, or null when dismissed.
Future<String?> showDirectoryBrowser(
  BuildContext context, {
  required OpenCodeClient client,
  required String initialPath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (sheetContext, scrollController) => _DirectoryBrowser(
        client: client,
        initialPath: initialPath,
        scrollController: scrollController,
      ),
    ),
  );
}

class _DirectoryBrowser extends StatefulWidget {
  final OpenCodeClient client;
  final String initialPath;
  final ScrollController scrollController;

  const _DirectoryBrowser({
    required this.client,
    required this.initialPath,
    required this.scrollController,
  });

  @override
  State<_DirectoryBrowser> createState() => _DirectoryBrowserState();
}

class _DirectoryBrowserState extends State<_DirectoryBrowser> {
  late String _currentPath;
  List<OpenCodeFileNode>? _entries;
  String? _error;
  bool _loading = true;

  /// Guards against an older listing landing after a newer navigation.
  int _navEpoch = 0;

  @override
  void initState() {
    super.initState();
    _currentPath = _normalize(widget.initialPath);
    _load();
  }

  static String _normalize(String path) {
    var p = path.trim();
    if (p.isEmpty) return '/';
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static String? _parentOf(String path) {
    if (path == '/') return null;
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return '/';
    return path.substring(0, idx);
  }

  Future<void> _load() async {
    final epoch = ++_navEpoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries =
          await widget.client.listFiles(directory: _currentPath);
      if (!mounted || epoch != _navEpoch) return;
      final dirs = entries.where((e) => e.isDirectory).toList()
        ..sort((a, b) {
          // Visible folders first, then dotfolders; alphabetical within each.
          final aDot = a.name.startsWith('.') ? 1 : 0;
          final bDot = b.name.startsWith('.') ? 1 : 0;
          if (aDot != bDot) return aDot - bDot;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      setState(() {
        _entries = dirs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _navEpoch) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _enter(OpenCodeFileNode dir) {
    final target = dir.absolute.isNotEmpty
        ? dir.absolute
        : '$_currentPath/${dir.name}';
    setState(() => _currentPath = _normalize(target));
    _load();
  }

  void _goUp() {
    final parent = _parentOf(_currentPath);
    if (parent == null) return;
    setState(() => _currentPath = parent);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final parent = _parentOf(_currentPath);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Icon(Icons.folder_open, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _currentPath,
                  style: theme.textTheme.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  // Keep the tail (folder name) visible when truncating.
                  textDirection: TextDirection.ltr,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(child: _buildList(theme, l10n, parent)),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.check),
                label: Text(l10n.useThisFolder),
                onPressed: () => Navigator.pop(context, _currentPath),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildList(
      ThemeData theme, AppLocalizations l10n, String? parent) {
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
              Icon(Icons.error_outline,
                  size: 40, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(l10n.couldNotListFolder,
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }

    final dirs = _entries ?? const [];
    return ListView(
      controller: widget.scrollController,
      children: [
        if (parent != null)
          ListTile(
            key: const ValueKey('dir-up'),
            leading: const Icon(Icons.arrow_upward),
            title: const Text('..'),
            dense: true,
            onTap: _goUp,
          ),
        if (dirs.isEmpty && parent != null)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Text(l10n.noSubfolders,
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          ),
        for (final dir in dirs)
          ListTile(
            key: ValueKey('dir-${dir.absolute.isNotEmpty ? dir.absolute : dir.name}'),
            leading: Icon(
              Icons.folder,
              color: dir.ignored
                  ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                  : theme.colorScheme.primary,
            ),
            title: Text(
              dir.name,
              style: dir.ignored
                  ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
                  : null,
            ),
            trailing: const Icon(Icons.chevron_right, size: 18),
            dense: true,
            onTap: () => _enter(dir),
          ),
      ],
    );
  }
}
