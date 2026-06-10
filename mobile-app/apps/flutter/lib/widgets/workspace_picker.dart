import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/workspace.dart';
import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/workspace_provider.dart';

/// Shows a bottom sheet for workspace selection.
///
/// Does NOT create a session -- it only sets OpenCodeProvider.directory.
/// The session is created lazily on the first message send.
Future<void> showWorkspacePicker(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<WorkspaceProvider>(),
      child: _WorkspacePickerSheet(
        machineStore: context.read<MachineStore>(),
        openCodeProvider: context.read<OpenCodeProvider>(),
        sessionProvider: context.read<SessionProvider>(),
        settingsProvider: context.read<SettingsProvider>(),
      ),
    ),
  );
}

class _WorkspacePickerSheet extends StatefulWidget {
  final MachineStore machineStore;
  final OpenCodeProvider openCodeProvider;
  final SessionProvider sessionProvider;
  final SettingsProvider settingsProvider;

  const _WorkspacePickerSheet({
    required this.machineStore,
    required this.openCodeProvider,
    required this.sessionProvider,
    required this.settingsProvider,
  });

  @override
  State<_WorkspacePickerSheet> createState() => _WorkspacePickerSheetState();
}

class _WorkspacePickerSheetState extends State<_WorkspacePickerSheet> {
  final _pathController = TextEditingController();
  String? _validationError;

  String? get _machineId => widget.machineStore.activeMachineId;

  @override
  void initState() {
    super.initState();
    final machineId = _machineId;
    if (machineId != null) {
      context.read<WorkspaceProvider>().loadForMachine(machineId);
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _selectWorkspace(String path) async {
    final provider = widget.openCodeProvider;
    final sessionProvider = widget.sessionProvider;

    if (provider.directory == path) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final hasActiveContext = provider.currentSessionId != null &&
        provider.history.isNotEmpty;
    final isStreaming = provider.isStreaming;

    if (isStreaming || hasActiveContext) {
      final confirmed = await _showConfirmDialog(isStreaming: isStreaming);
      if (confirmed != true) return;
    }

    if (provider.isStreaming) {
      await provider.abortSession();
    }

    provider.clearSession();
    sessionProvider.clearCurrentSession();
    provider.directory = path;

    final machineId = _machineId;
    if (machineId != null) {
      final ws = Workspace.fromPath(
        machineId: machineId,
        absolutePath: path,
        homeDir: widget.machineStore.activeMachine?.defaultDirectory ??
            widget.settingsProvider.settings.defaultDirectory,
      );
      if (mounted) {
        context.read<WorkspaceProvider>().addRecent(machineId, ws);
      }
    }

    if (mounted) Navigator.pop(context);
  }

  Future<bool?> _showConfirmDialog({bool isStreaming = false}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch workspace?'),
        content: Text(isStreaming
            ? 'An active stream will be stopped and the current chat context will be closed.'
            : 'Current chat context will be closed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );
  }

  void _submitManualPath() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() => _validationError = 'Path cannot be empty');
      return;
    }
    if (!path.startsWith('/')) {
      setState(() => _validationError = 'Path must be absolute (start with /)');
      return;
    }
    setState(() => _validationError = null);
    _selectWorkspace(path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final machineId = _machineId;
    final defaultDir = widget.machineStore.activeMachine?.defaultDirectory ??
        widget.settingsProvider.settings.defaultDirectory;
    final currentDir = widget.openCodeProvider.directory;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text('Workspace',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Default (~) option
                  if (defaultDir != null)
                    _WorkspaceTile(
                      icon: Icons.home_outlined,
                      title: 'Default (~)',
                      subtitle: defaultDir,
                      isActive: currentDir == defaultDir,
                      onTap: () => _selectWorkspace(defaultDir),
                    ),

                  // Favorites
                  if (machineId != null)
                    Consumer<WorkspaceProvider>(
                      builder: (_, wp, __) {
                        final favs = wp.getFavorites(machineId);
                        if (favs.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text('Favorites',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            ...favs.map((w) => _WorkspaceTile(
                                  icon: Icons.star,
                                  title: w.displayName,
                                  subtitle: w.shortPath,
                                  isActive: currentDir == w.path,
                                  onTap: () => _selectWorkspace(w.path),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.star,
                                        color: Colors.amber, size: 20),
                                    onPressed: () =>
                                        wp.toggleFavorite(machineId, w.path),
                                  ),
                                )),
                          ],
                        );
                      },
                    ),

                  // Recents
                  if (machineId != null)
                    Consumer<WorkspaceProvider>(
                      builder: (_, wp, __) {
                        final recents = wp.getRecents(machineId);
                        final favPaths =
                            wp.getFavorites(machineId).map((w) => w.path).toSet();
                        final nonFavRecents = recents
                            .where((w) => !favPaths.contains(w.path))
                            .toList();
                        if (nonFavRecents.isEmpty) return const SizedBox.shrink();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 8),
                            Text('Recent',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            ...nonFavRecents.map((w) => _WorkspaceTile(
                                  icon: Icons.history,
                                  title: w.displayName,
                                  subtitle: w.shortPath,
                                  isActive: currentDir == w.path,
                                  onTap: () => _selectWorkspace(w.path),
                                  trailing: IconButton(
                                    icon: Icon(Icons.star_border,
                                        size: 20,
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                    onPressed: () =>
                                        wp.toggleFavorite(machineId, w.path),
                                  ),
                                )),
                          ],
                        );
                      },
                    ),

                  // Manual path entry
                  const SizedBox(height: 16),
                  Text('Manual path',
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _pathController,
                          decoration: InputDecoration(
                            hintText: '/home/user/projects/my-app',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            errorText: _validationError,
                          ),
                          onSubmitted: (_) => _submitManualPath(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _submitManualPath,
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isActive;
  final VoidCallback onTap;
  final Widget? trailing;

  const _WorkspaceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isActive = false,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon,
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant),
      title: Text(title,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? theme.colorScheme.primary : null,
          )),
      subtitle:
          Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
