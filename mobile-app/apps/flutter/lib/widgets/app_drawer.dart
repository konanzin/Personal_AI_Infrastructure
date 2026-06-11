import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import 'machine_selector.dart';
import '../l10n/app_localizations.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context
          .read<SessionProvider>()
          .loadSessions(directory: context.read<OpenCodeProvider>().directory);
    });
  }

  Future<void> _createNewSession() async {
    final sessionProvider = context.read<SessionProvider>();
    final openCodeProvider = context.read<OpenCodeProvider>();
    // Lazy: clear state, session will be created on first message send
    openCodeProvider.clearSession();
    await sessionProvider.clearCurrentSession(
      machineId: context.read<MachineStore>().activeMachineId,
      directory: openCodeProvider.directory,
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _openSession(Session session) async {
    final sessionProvider = context.read<SessionProvider>();
    final openCodeProvider = context.read<OpenCodeProvider>();
    if (session.directory != null) {
      openCodeProvider.directory = session.directory;
    }
    await sessionProvider.selectSession(
      session.id,
      machineId: context.read<MachineStore>().activeMachineId,
      directory: session.directory ?? openCodeProvider.directory,
    );
    await openCodeProvider.switchSession(session.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _renameSession(String sessionId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.rename),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
              hintText: AppLocalizations.of(ctx)!.sessionName),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: Text(AppLocalizations.of(ctx)!.save)),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty && mounted) {
      await context
          .read<SessionProvider>()
          .renameSession(sessionId, result.trim());
    }
    controller.dispose();
  }

  Future<void> _deleteSession(String sessionId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(ctx)!.deleteQuestion),
        content: Text(AppLocalizations.of(ctx)!.deleteConfirmBody(name)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(AppLocalizations.of(ctx)!.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final provider = context.read<SessionProvider>();
      final directory = context.read<OpenCodeProvider>().directory;
      await provider.deleteSession(sessionId);
      await provider.loadSessions(directory: directory);
    }
  }

  void _showSessionActions(Session session) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(AppLocalizations.of(context)!.rename),
              onTap: () {
                Navigator.pop(ctx);
                Future.microtask(
                    () => _renameSession(session.id, session.displayName));
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(ctx).colorScheme.error),
              title: Text(AppLocalizations.of(context)!.delete,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
              onTap: () {
                Navigator.pop(ctx);
                Future.microtask(
                    () => _deleteSession(session.id, session.displayName));
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat('EEE').format(date);
    return DateFormat('MMM d').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessionProvider = context.watch<SessionProvider>();
    final sessions = sessionProvider.sessions;
    final currentId = sessionProvider.currentSessionId;

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text('PAI', style: theme.textTheme.titleLarge),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: MachineSelector(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.terminal, size: 22),
                    tooltip: AppLocalizations.of(context)!.terminal,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/terminal');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.extension_outlined, size: 22),
                    tooltip: AppLocalizations.of(context)!.aiProviders,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/providers');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 22),
                    tooltip: AppLocalizations.of(context)!.settings,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.pushNamed(context, '/settings');
                    },
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // New chat button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _createNewSession,
                  icon: const Icon(Icons.add, size: 20),
                  label: Text(AppLocalizations.of(context)!.newChat),
                  style: TextButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

            // Section label
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Text(
                'Recentes',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Sessions list
            Expanded(
              child: sessionProvider.isLoading && sessions.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final isActive = session.id == currentId;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Material(
                            color: isActive
                                ? theme.colorScheme.primary.withAlpha(25)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _openSession(session),
                              onLongPress: () => _showSessionActions(session),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            session.displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isActive
                                                  ? theme.colorScheme.primary
                                                  : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          if (session.directory != null)
                                            Text(
                                              session.directory!
                                                  .split('/')
                                                  .lastWhere(
                                                      (s) => s.isNotEmpty,
                                                      orElse: () =>
                                                          session.directory!),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                fontSize: 11,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDate(session.updated),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
