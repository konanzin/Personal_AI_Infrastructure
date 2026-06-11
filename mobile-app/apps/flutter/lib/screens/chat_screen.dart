import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/client_provider.dart';
import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/git_status_service.dart';
import '../services/ssh_gate_service.dart';
import '../services/ssh_service.dart';
import '../widgets/git_status_badge.dart';
import '../widgets/workspace_picker.dart';
import '../services/voice_service.dart';
import '../widgets/date_header.dart';
import '../widgets/chat_permission_area.dart';
import '../models/chat_message.dart';
import '../models/file_change.dart';
import '../models/message_part.dart';
import '../services/chat_formatting.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chat_autocomplete_controller.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_message_tile.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';

// ── Chat list item helper ────────────────────────────────────────────────

class _ChatListItem {
  final ChatMessage? message;
  final DateTime? date;
  final int? historyIndex;
  final bool isDateHeader;

  const _ChatListItem.message(this.message, this.historyIndex)
      : date = null,
        isDateHeader = false;

  const _ChatListItem.date(this.date)
      : message = null,
        historyIndex = null,
        isDateHeader = true;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _isLoading = true;
  String? _error;
  OpenCodeProvider? _provider;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final VoiceService _voiceService = VoiceService();
  final List<File> _pendingAttachments = [];
  bool _showScrollToBottom = false;
  GitStatus? _gitStatus;
  String? _gitStatusDirectory;
  StreamSubscription? _sendSubscription;
  bool _isSearching = false;
  final TextEditingController _chatSearchController = TextEditingController();
  List<int> _searchMatchIndices = [];
  int _currentSearchMatch = -1;

  late final ChatAutocompleteController _autocomplete;

  // Memoized stylesheet — rebuilt only when theme changes
  MarkdownStyleSheet? _cachedMarkdownStyleSheet;
  ThemeData? _lastTheme;

  // Memoized chat items — rebuilt only when history length changes
  List<_ChatListItem>? _cachedChatItems;
  int _cachedHistoryLength = -1;
  String? _cachedSessionId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _autocomplete = ChatAutocompleteController(
      textController: _textController,
      provider: () => _provider,
      context: () => context,
      mounted: () => mounted,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  void _onScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.offset >
            _scrollController.position.minScrollExtent + 200;
    if (show != _showScrollToBottom) setState(() => _showScrollToBottom = show);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    try {
      context.read<ClientProvider>().removeListener(_onClientReady);
    } catch (_) {}
    _sendSubscription?.cancel();
    _autocomplete.dispose();
    _voiceService.dispose();
    _textController.dispose();
    _chatSearchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final provider = context.read<OpenCodeProvider>();
    final clientProvider = context.read<ClientProvider>();

    if (clientProvider.client == null) {
      // Client may still be initializing — listen for changes
      clientProvider.addListener(_onClientReady);
      setState(() {
        _isLoading = false;
        _error = AppLocalizations.of(context)!.serverNotConfigured;
      });
      return;
    }

    _doInitialize(provider, clientProvider);
  }

  void _onClientReady() {
    final clientProvider = context.read<ClientProvider>();
    if (clientProvider.client != null) {
      clientProvider.removeListener(_onClientReady);
      final provider = context.read<OpenCodeProvider>();
      _doInitialize(provider, clientProvider);
    }
  }

  Future<void> _doInitialize(
      OpenCodeProvider provider, ClientProvider clientProvider) async {
    if (provider.clientOrNull != clientProvider.client) {
      provider.updateClient(clientProvider.client!);
    }

    final sessionProvider = context.read<SessionProvider>();
    final machineStore = context.read<MachineStore>();
    final machineId = machineStore.activeMachineId;

    // Apply default directory before restoring the active session, because the
    // persisted session is scoped by machine + directory.
    if (provider.directory == null) {
      final defaultDir = machineStore.activeMachine?.defaultDirectory ??
          context.read<SettingsProvider>().settings.defaultDirectory;
      if (defaultDir != null) {
        provider.directory = defaultDir;
      }
    }

    await sessionProvider.loadPersistedSession(
      machineId: machineId,
      directory: provider.directory,
    );
    if (!mounted) return;

    var sessionId = sessionProvider.currentSessionId;
    if (sessionId != null) {
      // Bijective session rule: never attach a restored session that no
      // longer exists or belongs to a different directory on this machine.
      final scopeOk = await sessionProvider.verifySessionScope(
        sessionId,
        expectedDirectory: provider.directory,
      );
      if (!mounted) return;
      if (!scopeOk) {
        await sessionProvider.clearCurrentSession(
          machineId: machineId,
          directory: provider.directory,
        );
        if (provider.currentSessionId == sessionId) {
          provider.clearSession();
        }
        sessionId = null;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                AppLocalizations.of(context)!.savedSessionOtherDirectory),
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }
    if (sessionId != null) {
      try {
        if (sessionId != provider.currentSessionId) {
          await provider.switchSession(sessionId);
        } else if (provider.history.isEmpty) {
          await provider.loadHistory();
        }
      } catch (e) {
        debugPrint('[PAI_UI] Failed to load session history: $e');
        if (mounted) {
          setState(() {
            _error = AppLocalizations.of(context)!.failedLoadHistory('$e');
            _isLoading = false;
          });
          return;
        }
      }
    }

    if (!mounted) return;

    _cachedChatItems = null;
    _cachedHistoryLength = -1;
    _cachedSessionId = null;

    _fetchGitStatusIfNeeded(provider.directory);

    setState(() {
      _provider = provider;
      _isLoading = false;
      _error = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _provider == null) return;

    _autocomplete.dismiss();
    _textController.clear();
    final attachments = <FileAttachment>[];
    for (final f in _pendingAttachments) {
      attachments.add(FileAttachment(
        name: f.path.split('/').last,
        mimeType: guessMimeType(f.path),
        bytes: await f.readAsBytes(),
      ));
    }
    if (!mounted) return;
    setState(() => _pendingAttachments.clear());
    FocusScope.of(context).unfocus();

    // Handle slash commands
    if (_handleSlashCommand(text)) return;

    if (_provider!.currentSessionId == null) {
      try {
        await _provider!.createSession();
        final sessionId = _provider!.currentSessionId;
        if (sessionId != null && mounted) {
          await context.read<SessionProvider>().selectSession(
                sessionId,
                machineId: context.read<MachineStore>().activeMachineId,
                directory: _provider!.directory,
              );
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = AppLocalizations.of(context)!.failedCreateSession('$e');
          });
        }
        return;
      }
    }

    _sendSubscription?.cancel();
    _sendSubscription =
        _provider!.sendMessageStream(text, attachments: attachments).listen(
      (_) {},
      onDone: () {
        _sendSubscription = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.minScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      },
      onError: (error) {
        _sendSubscription = null;
        debugPrint('Error in message stream: $error');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(AppLocalizations.of(context)!.errorWithDetail('$error')),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: AppLocalizations.of(context)!.retry,
              onPressed: () {
                _textController.text = text;
                _sendMessage();
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _sendVoiceText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.text = trimmed;
    await _sendMessage();
  }

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(AppLocalizations.of(context)!.camera),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(AppLocalizations.of(context)!.gallery),
              onTap: () {
                Navigator.pop(ctx);
                _pickFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: Text(AppLocalizations.of(context)!.file),
              onTap: () {
                Navigator.pop(ctx);
                _pickFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.camera);
    if (xfile != null) {
      setState(() => _pendingAttachments.add(File(xfile.path)));
    }
  }

  Future<void> _pickFromGallery() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile != null) {
      setState(() => _pendingAttachments.add(File(xfile.path)));
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _pendingAttachments.add(File(result.files.single.path!)));
    }
  }


  // ── Git status ──────────────────────────────────────────────────────────

  void _fetchGitStatusIfNeeded(String? directory) {
    if (directory == null || directory == _gitStatusDirectory) return;
    _gitStatusDirectory = directory;

    final machine = context.read<MachineStore>().activeMachine;
    final ssh = machine?.ssh;
    if (ssh == null || machine == null) {
      _gitStatus = null;
      return;
    }

    // Git status is a background, read-only nicety. Only use the SSH
    // credential if it's already unlocked this session — never trigger a
    // surprise auth prompt just for a directory change.
    if (!SshGateService.isUnlocked(machine.id)) {
      _gitStatus = null;
      return;
    }

    final sshService = SshService();
    () async {
      try {
        await sshService.connect(
          host: ssh.host,
          port: ssh.port,
          username: ssh.username,
          privateKeyPem: ssh.privateKey,
          password: ssh.password,
          expectedHostKeyFingerprint: ssh.hostKeyFingerprint,
        );
        final status = await GitStatusService(sshService).getStatus(directory);
        if (mounted && _gitStatusDirectory == directory) {
          setState(() => _gitStatus = status);
        }
      } catch (_) {
        // SSH unavailable -- silently skip git status
      } finally {
        sshService.disconnect();
      }
    }();
  }

  // ── Menu actions ────────────────────────────────────────────────────────

  String _shortenPath(String path) {
    final machine = context.read<MachineStore>().activeMachine;
    final defaultDir = machine?.defaultDirectory ??
        context.read<SettingsProvider>().settings.defaultDirectory;
    if (defaultDir != null && path.startsWith(defaultDir)) {
      final suffix = path.substring(defaultDir.length);
      return suffix.isEmpty ? '~' : '~$suffix';
    }
    return path;
  }

  void _showWorkspacePicker() {
    showWorkspacePicker(context);
  }

  String _getModelDisplayName() {
    if (_provider == null) return 'PAI';
    final override = _provider!.modelOverride;
    if (override != null) {
      return override['modelID'] ?? 'Custom';
    }
    final info = _provider!.sessionInfo;
    if (info != null) {
      final model = info['model'];
      if (model is Map) return model['id']?.toString() ?? 'PAI';
      if (model is String) return model;
    }
    return 'PAI';
  }

  Future<void> _createNewChat() async {
    final sessionProvider = context.read<SessionProvider>();
    final openCodeProvider = context.read<OpenCodeProvider>();
    // Lazy: just clear state without creating a server-side session.
    // The session will be created when the user sends their first message.
    openCodeProvider.clearSession();
    await sessionProvider.clearCurrentSession(
      machineId: context.read<MachineStore>().activeMachineId,
      directory: openCodeProvider.directory,
    );
    if (_provider == null) {
      setState(() => _provider = openCodeProvider);
    }
    _cachedChatItems = null;
    _cachedHistoryLength = -1;
    _cachedSessionId = null;
    setState(() {});
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'model':
        _showModelPicker();
      case 'todos':
        _showTodosDialog();
      case 'share':
        _shareSession();
      case 'info':
        _showSessionInfo();
      case 'summarize':
        _summarizeSession();
    }
  }

  Future<void> _summarizeSession() async {
    if (_provider == null) return;
    final result = await _provider!.summarizeSession();
    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.sessionSummarized)),
      );
    }
  }

  Future<void> _showModelPicker() async {
    if (_provider == null) return;
    try {
      final clientProvider = context.read<ClientProvider>();
      final providers = await clientProvider.getProviders();
      if (!mounted) return;

      final allRaw = providers['all'] ?? providers['providers'];
      final List allList;
      if (allRaw is List) {
        allList = allRaw;
      } else if (providers.values.any((v) => v is List)) {
        allList = providers.values.whereType<List>().expand((l) => l).toList();
      } else {
        allList = [];
      }

      final models = <Map<String, String>>[];
      for (final prov in allList) {
        if (prov is! Map) continue;
        final provId = prov['id']?.toString() ?? prov['name']?.toString() ?? '';
        final provModels = prov['models'];
        if (provModels is Map) {
          for (final mId in provModels.keys) {
            models.add({'providerID': provId, 'modelID': mId.toString()});
          }
        } else if (provModels is List) {
          for (final m in provModels) {
            final mId = m is Map
                ? (m['id']?.toString() ?? m['name']?.toString() ?? '')
                : m.toString();
            if (mId.isNotEmpty) {
              models.add({'providerID': provId, 'modelID': mId});
            }
          }
        }
      }

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
            content:
                Text(AppLocalizations.of(context)!.noModelsAvailable)),
          );
        }
        return;
      }

      final current = _provider!.modelOverride;

      // Group models by provider
      final grouped = <String, List<Map<String, String>>>{};
      for (final m in models) {
        grouped.putIfAbsent(m['providerID']!, () => []).add(m);
      }

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          return DraggableScrollableSheet(
            initialChildSize: 0.5,
            maxChildSize: 0.85,
            minChildSize: 0.3,
            expand: false,
            builder: (ctx, scrollController) => Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child:
                      Text(AppLocalizations.of(context)!.selectModel,
                          style: theme.textTheme.titleMedium),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(AppLocalizations.of(context)!.defaultServerModel),
                  trailing: current == null
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () {
                    _provider!.modelOverride = null;
                    Navigator.pop(ctx);
                  },
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    children: [
                      for (final entry in grouped.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            entry.key.toUpperCase(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        for (final m in entry.value)
                          ListTile(
                            dense: true,
                            title: Text(m['modelID']!),
                            trailing: (current != null &&
                                    current['providerID'] == m['providerID'] &&
                                    current['modelID'] == m['modelID'])
                                ? Icon(Icons.check,
                                    color: theme.colorScheme.primary, size: 20)
                                : null,
                            onTap: () {
                              _provider!.modelOverride = m;
                              Navigator.pop(ctx);
                            },
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.failedLoadModels('$e'))),
        );
      }
    }
  }

  Future<void> _showTodosDialog() async {
    if (_provider == null) return;
    await _provider!.loadTodos();
    if (!mounted) return;
    final todos = _provider!.todos;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(AppLocalizations.of(context)!.sessionTodos,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (todos.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(AppLocalizations.of(context)!.noTodos),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: todos.length,
                  itemBuilder: (_, i) {
                    final todo = todos[i];
                    final content = todo['content'] as String? ?? '';
                    final status = todo['status'] as String? ?? 'pending';
                    return ListTile(
                      leading: Icon(
                        status == 'completed'
                            ? Icons.check_circle
                            : status == 'in_progress'
                                ? Icons.play_circle
                                : Icons.circle_outlined,
                        color: status == 'completed'
                            ? Theme.of(ctx).semanticColors.success
                            : status == 'in_progress'
                                ? Theme.of(ctx).semanticColors.warning
                                : null,
                      ),
                      title: Text(content),
                      subtitle: Text(status),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareSession() async {
    if (_provider == null) return;
    final share = await _provider!.shareSession();
    if (mounted) {
      if (share != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.shareLinkMessage(share))),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.shareCreated)),
        );
      }
    }
  }

  Future<void> _showSessionInfo() async {
    if (_provider == null) return;
    await _provider!.loadSessionInfo();
    if (!mounted) return;

    final info = _provider!.sessionInfo;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(AppLocalizations.of(context)!.noSessionInfo)),
      );
      return;
    }

    List<dynamic> children = [];
    try {
      children = await _provider!.client.getSessionChildren(info['id'] ?? '');
    } catch (_) {}

    if (!mounted) return;

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppLocalizations.of(ctx)!.sessionInfo,
                  style: Theme.of(ctx).textTheme.titleMedium),
              const Divider(),
              _infoRow(AppLocalizations.of(ctx)!.modelLabel, _formatModel(info)),
              _infoRow('Agent', info['agent'] ?? 'default'),
              if (info['cost'] != null) _infoRow('Cost', '\$${info['cost']}'),
              if (info['tokens'] != null)
                _infoRow('Tokens', formatTokenUsage(info['tokens'])),
              if (info['directory'] != null)
                _infoRow('Directory', info['directory']),
              if (info['parentID'] != null)
                _infoRow('Parent', info['parentID']),
              if (info['share'] != null) _infoRow('Share', '${info['share']}'),
              _infoRow('ID', info['id'] ?? '-'),
              if (children.isNotEmpty) ...[
                const Divider(),
                Text(AppLocalizations.of(ctx)!.childSessions(children.length),
                    style: Theme.of(ctx).textTheme.labelLarge),
                ...children.take(5).map((c) {
                  final title =
                      c is Map ? (c['title'] ?? c['id'] ?? '-') : '$c';
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child:
                        Text('- $title', style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatModel(Map<String, dynamic> info) {
    final m = info['model'];
    if (m is Map) return '${m['id'] ?? '?'} (${m['providerID'] ?? '?'})';
    return info['modelID']?.toString() ?? 'default';
  }


  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child:
                Text('$value', style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  /// Handles slash commands typed in the input (e.g. /compact, /model).
  bool _handleSlashCommand(String text) {
    if (!text.startsWith('/') ||
        _provider == null ||
        _provider!.currentSessionId == null) {
      return false;
    }
    final parts = text.split(RegExp(r'\s+'));
    final command = parts[0].substring(1);
    final args = parts.length > 1 ? parts.sublist(1).join(' ') : null;

    _provider!.client
        .executeCommand(
      _provider!.currentSessionId!,
      command,
      arguments: args,
    )
        .then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(AppLocalizations.of(context)!
                  .commandExecuted(command))),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  AppLocalizations.of(context)!.commandFailed('$e'))),
        );
      }
    });

    return true;
  }

  // ── Date-grouped chat list helpers ───────────────────────────────────────

  /// Builds the flat list of [_ChatListItem] with date headers inserted.
  /// The result is reversed so index 0 is the newest item (bottom of screen
  /// because [ListView] uses `reverse: true`).
  List<_ChatListItem> _buildChatItems() {
    if (_provider == null) return [];

    final currentLength = _provider!.history.length;
    final currentSessionId = _provider!.currentSessionId;
    if (_cachedChatItems != null &&
        _cachedHistoryLength == currentLength &&
        _cachedSessionId == currentSessionId) {
      return _cachedChatItems!;
    }

    final items = <_ChatListItem>[];
    DateTime? lastDate;

    for (int i = 0; i < currentLength; i++) {
      final messageId = _provider!.getMessageIdAt(i);
      final timestamp =
          messageId != null ? _provider!.getMessageTimestamp(messageId) : null;

      if (timestamp != null) {
        final date = DateTime(timestamp.year, timestamp.month, timestamp.day);
        if (lastDate == null || date != lastDate) {
          items.add(_ChatListItem.date(date));
          lastDate = date;
        }
      }

      items.add(_ChatListItem.message(_provider!.history.elementAt(i), i));
    }

    _cachedChatItems = items.reversed.toList();
    _cachedHistoryLength = currentLength;
    _cachedSessionId = currentSessionId;
    return _cachedChatItems!;
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(ThemeData theme) {
    return MarkdownStyleSheet(
      p: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
      a: TextStyle(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline),
      strong: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
          fontWeight: FontWeight.bold),
      em: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 16,
          fontStyle: FontStyle.italic),
      code: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 14,
          backgroundColor: theme.colorScheme.surfaceContainerHighest),
      codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8)),
      listBullet: TextStyle(color: theme.colorScheme.onSurface, fontSize: 16),
      h1: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold),
      h2: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 18,
          fontWeight: FontWeight.bold),
      h3: TextStyle(
          color: theme.colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.bold),
      blockquote: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 16,
          fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4)),
      tableHead: TextStyle(
          fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
      tableBody: TextStyle(color: theme.colorScheme.onSurface),
      tableBorder:
          TableBorder.all(color: theme.colorScheme.outlineVariant, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_lastTheme != theme) {
      _lastTheme = theme;
      _cachedMarkdownStyleSheet = _buildMarkdownStyleSheet(theme);
    }

    final currentDir = _provider?.directory;
    if (currentDir != _gitStatusDirectory) {
      _fetchGitStatusIfNeeded(currentDir);
    }

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: _isSearching
            ? _buildChatSearchField()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => _showModelPicker(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getModelDisplayName(),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_more, size: 20),
                      ],
                    ),
                  ),
                  if (_provider?.directory != null)
                    GestureDetector(
                      onTap: () => _showWorkspacePicker(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _shortenPath(_provider!.directory!),
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_gitStatus?.branch != null) ...[
                            const SizedBox(width: 6),
                            GitStatusInline(status: _gitStatus!),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
        centerTitle: false,
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search, size: 22),
              onPressed: () => setState(() => _isSearching = true),
            ),
          if (_isSearching && _searchMatchIndices.isNotEmpty) ...[
            Text('${_currentSearchMatch + 1}/${_searchMatchIndices.length}',
                style: const TextStyle(fontSize: 12)),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed:
                  _currentSearchMatch > 0 ? () => _navigateSearch(-1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: _currentSearchMatch < _searchMatchIndices.length - 1
                  ? () => _navigateSearch(1)
                  : null,
            ),
          ],
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _isSearching = false;
                _chatSearchController.clear();
                _searchMatchIndices = [];
                _currentSearchMatch = -1;
              }),
            ),
          if (!_isSearching) ...[
            IconButton(
              icon: const Icon(Icons.edit_square, size: 22),
              onPressed: _createNewChat,
            ),
            if (_provider != null)
              AnimatedBuilder(
                animation: _provider!,
                builder: (context, child) {
                  return PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 22),
                    onSelected: (value) => _handleMenuAction(value),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'todos',
                        child: ListTile(
                          leading: const Icon(Icons.checklist),
                          title: Text(AppLocalizations.of(context)!.todos),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: const Icon(Icons.share),
                          title: Text(AppLocalizations.of(context)!.share),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'info',
                        child: ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(AppLocalizations.of(context)!.sessionInfo),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'summarize',
                        child: ListTile(
                          leading: const Icon(Icons.summarize),
                          title: Text(AppLocalizations.of(context)!.summarize),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildChatSearchField() {
    return TextField(
      controller: _chatSearchController,
      autofocus: true,
      decoration: InputDecoration(
        hintText: AppLocalizations.of(context)!.searchInChat,
        border: InputBorder.none,
      ),
      style: const TextStyle(fontSize: 16),
      onChanged: (v) {
        final query = v.toLowerCase();
        setState(() {
          if (query.isEmpty) {
            _searchMatchIndices = [];
            _currentSearchMatch = -1;
            return;
          }
          final history = _provider?.history.toList() ?? <ChatMessage>[];
          _searchMatchIndices = [];
          for (var i = 0; i < history.length; i++) {
            final text = history[i].text ?? '';
            if (text.toLowerCase().contains(query)) {
              _searchMatchIndices.add(i);
            }
          }
          _currentSearchMatch = _searchMatchIndices.isNotEmpty ? 0 : -1;
        });
        if (_searchMatchIndices.isNotEmpty) _scrollToSearchMatch();
      },
    );
  }

  void _navigateSearch(int delta) {
    setState(() => _currentSearchMatch += delta);
    _scrollToSearchMatch();
  }

  void _scrollToSearchMatch() {
    if (_currentSearchMatch < 0 ||
        _currentSearchMatch >= _searchMatchIndices.length) {
      return;
    }
    final histIdx = _searchMatchIndices[_currentSearchMatch];
    final chatItems = _buildChatItems();
    final listIdx = chatItems.indexWhere((ci) => ci.historyIndex == histIdx);
    if (listIdx < 0 || !_scrollController.hasClients) return;
    final estimate = listIdx * 80.0;
    _scrollController.animateTo(
      estimate,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.initializingChat),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.settings),
                label: Text(AppLocalizations.of(context)!.goToSettings),
              ),
            ],
          ),
        ),
      );
    }

    if (_provider == null) {
      return _buildEmptyState(context);
    }

    return AnimatedBuilder(
      animation: _provider!,
      builder: (context, child) {
        final chatItems = _buildChatItems();
        final pendingPerms = _provider!.pendingPermissions.values.toList();
        final pendingQs = _provider!.pendingQuestions.values.toList();
        final lastError = _provider!.lastError;
        final isStreaming = _provider!.isStreaming;

        return Column(
          children: [
            if (lastError != null)
              MaterialBanner(
                content: Text(lastError,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Icon(Icons.error_outline,
                    color: Theme.of(context).colorScheme.error),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                actions: [
                  if (lastError.contains('load history'))
                    TextButton(
                      onPressed: () async {
                        _provider!.clearError();
                        try {
                          await _provider!.loadHistory();
                        } catch (e) {
                          debugPrint('[PAI_UI] Retry loadHistory failed: $e');
                        }
                      },
                      child: Text(AppLocalizations.of(context)!.retry),
                    ),
                  TextButton(
                    onPressed: () => _provider!.clearError(),
                    child: Text(AppLocalizations.of(context)!.dismiss),
                  ),
                ],
              ),

            Expanded(
              child: Stack(
                children: [
                  if (chatItems.isEmpty && !isStreaming)
                    _buildEmptyState(context)
                  else
                    ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      padding: const EdgeInsets.all(16),
                      itemCount: chatItems.length,
                      itemBuilder: (context, index) {
                        final item = chatItems[index];
                        if (item.isDateHeader) {
                          return DateHeader(
                            key: ValueKey('date-${item.date}'),
                            date: item.date!,
                          );
                        }
                        return KeyedSubtree(
                          key: ValueKey('msg-${item.historyIndex}'),
                          child: _buildMessageBubble(
                            item.message!,
                            item.historyIndex!,
                          ),
                        );
                      },
                    ),
                  if (_showScrollToBottom)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: FloatingActionButton.small(
                        heroTag: 'scrollBottom',
                        onPressed: () => _scrollController.animateTo(
                          _scrollController.position.minScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOut,
                        ),
                        child: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ),
                ],
              ),
            ),

            if (isStreaming)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    _TypingDots(),
                    const SizedBox(width: 8),
                    Text(AppLocalizations.of(context)!.generating,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ],
                ),
              ),

            ChatPermissionArea(
              pendingPermissions: pendingPerms,
              pendingQuestions: pendingQs,
              onPermissionReply: (id, reply) =>
                  _provider!.replyToPermission(id, reply),
              onQuestionReply: (id, answers) =>
                  _provider!.replyToQuestion(id, answers),
              onQuestionReject: (id) => _provider!.rejectQuestion(id),
            ),

            if (isStreaming)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextButton.icon(
                  onPressed: () => _provider!.abortSession(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: Text(AppLocalizations.of(context)!.stop),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),

            // Input bar passed as child — not rebuilt on provider notifications
            child!,
          ],
        );
      },
      child: _buildInput(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology,
            size: 64,
            color: theme.colorScheme.primary.withAlpha(180),
          ),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.chatEmptyTitle,
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.chatEmptySubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index) {
    final isUser = message.origin == MessageOrigin.user;
    final messageId = _provider?.getMessageIdAt(index);

    DateTime? timestamp;
    if (messageId != null) {
      timestamp = _provider!.getMessageTimestamp(messageId);
    }

    String? reasoning;
    List<ToolCallPart> toolCalls = const [];
    List<ShellPart> shellCommands = const [];
    List<FileChange> fileChanges = const [];
    List<AnsweredQuestionData> answeredQuestions = const [];
    if (!isUser && messageId != null) {
      reasoning = _provider!.getReasoningForHistoryIndex(index);
      toolCalls = _provider!
          .getToolCallsForMessage(messageId)
          .where((tc) => !_qaHiddenTools.contains(tc.name.toLowerCase()))
          .toList();
      shellCommands = _provider!.getShellCommandsForMessage(messageId);
      fileChanges = _provider!.getFileChangesForMessage(messageId);
      answeredQuestions = _provider!.getAnsweredQuestionsForMessage(messageId);
    }

    final showThinking = context.read<SettingsProvider>().showThinking;
    if (!showThinking) reasoning = null;

    final isLastMessage = index == _provider!.history.length - 1;
    final isActivelyStreaming =
        !isUser && _provider!.isStreaming && isLastMessage;

    return ChatMessageTile(
      message: message,
      historyIndex: index,
      displayText: _buildDisplayText(message, index),
      timestamp: timestamp,
      reasoning: reasoning,
      onLongPress: () => _showMessageActions(message, index),
      isStreaming: isActivelyStreaming,
      markdownStyleSheet: _cachedMarkdownStyleSheet,
      toolCalls: toolCalls,
      shellCommands: shellCommands,
      fileChanges: fileChanges,
      answeredQuestions: answeredQuestions,
    );
  }

  void _showMessageActions(ChatMessage message, int index) {
    final isUser = message.origin == MessageOrigin.user;
    final messageId = _provider?.getMessageIdAt(index);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(AppLocalizations.of(context)!.copy),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text ?? ''));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(AppLocalizations.of(context)!.copied),
                      duration: const Duration(seconds: 1)),
                );
              },
            ),
            if (!isUser && messageId != null) ...[
              ListTile(
                leading: const Icon(Icons.undo),
                title: Text(AppLocalizations.of(context)!.revertChanges),
                subtitle: Text(AppLocalizations.of(context)!.revertChangesSubtitle),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _provider!.revertMessage(messageId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(ok
                              ? AppLocalizations.of(context)!.reverted
                              : AppLocalizations.of(context)!.revertFailed)),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.fork_right),
                title: Text(AppLocalizations.of(context)!.forkFromHere),
                subtitle: Text(AppLocalizations.of(context)!.forkSubtitle),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newId = await _provider!.forkSession(messageId);
                  if (newId != null && mounted) {
                    await context.read<SessionProvider>().selectSession(
                          newId,
                          machineId:
                              context.read<MachineStore>().activeMachineId,
                          directory: _provider!.directory,
                        );
                    if (mounted) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const ChatScreen()),
                      );
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Builds tool call bubbles for a message at the given index.
  /// Returns an empty list if no tool calls are associated.
  static const _qaHiddenTools = {'question', 'ask', 'todowrite'};

  String _buildDisplayText(ChatMessage message, int index) {
    return message.text ?? '';
  }

  Widget _buildInput() {
    return ChatInputBar(
      controller: _textController,
      layerLink: _autocomplete.layerLink,
      voiceService: _voiceService,
      pendingAttachments: _pendingAttachments,
      onSend: _sendMessage,
      onAttach: _showAttachmentPicker,
      onVoiceResult: _sendVoiceText,
      onRemoveAttachment: (i) =>
          setState(() => _pendingAttachments.removeAt(i)),
      guessMime: guessMimeType,
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final scale = 0.5 + 0.5 * (t < 0.5 ? t * 2 : 2.0 - t * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
