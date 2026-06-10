import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/client_provider.dart';
import '../providers/machine_store.dart';
import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import '../providers/settings_provider.dart';
import '../services/git_status_service.dart';
import '../services/ssh_service.dart';
import '../widgets/git_status_badge.dart';
import '../widgets/workspace_picker.dart';
import '../services/voice_service.dart';
import '../widgets/date_header.dart';
import '../widgets/chat_permission_area.dart';
import '../models/file_change.dart';
import '../models/message_part.dart';
import '../widgets/autocomplete_overlay.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_message_tile.dart';

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

  // Autocomplete state
  final LayerLink _inputLayerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<AutocompleteSuggestion> _acSuggestions = [];
  int _acHighlight = -1;
  String _acTrigger = ''; // '/' or '@'
  int _acTriggerOffset = 0; // cursor offset where trigger started
  List<dynamic>? _cachedCommands;
  int _acDebounceSeq = 0;

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
    _textController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  void _onScroll() {
    final show = _scrollController.hasClients &&
        _scrollController.offset > _scrollController.position.minScrollExtent + 200;
    if (show != _showScrollToBottom) setState(() => _showScrollToBottom = show);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _textController.removeListener(_onTextChanged);
    try {
      context.read<ClientProvider>().removeListener(_onClientReady);
    } catch (_) {}
    _sendSubscription?.cancel();
    _dismissOverlay();
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
        _error = 'Server not configured. Please go to Settings.';
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

  Future<void> _doInitialize(OpenCodeProvider provider, ClientProvider clientProvider) async {
    if (provider.clientOrNull != clientProvider.client) {
      provider.updateClient(clientProvider.client!);
    }

    final sessionProvider = context.read<SessionProvider>();
    if (sessionProvider.currentSessionId == null) {
      await sessionProvider.loadPersistedSession();
    }
    if (!mounted) return;

    final sessionId = sessionProvider.currentSessionId;
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
            _error = 'Failed to load session history: $e';
            _isLoading = false;
          });
          return;
        }
      }
    }

    if (!mounted) return;

    // Apply default directory only when no session is active and no directory set
    if (sessionId == null && provider.directory == null) {
      final machine = context.read<MachineStore>().activeMachine;
      final defaultDir = machine?.defaultDirectory ??
          context.read<SettingsProvider>().settings.defaultDirectory;
      if (defaultDir != null) {
        provider.directory = defaultDir;
      }
    }
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
    
    _dismissOverlay();
    _textController.clear();
    final attachments = <FileAttachment>[];
    for (final f in _pendingAttachments) {
      attachments.add(FileAttachment(
        name: f.path.split('/').last,
        mimeType: _guessMime(f.path),
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
          await context.read<SessionProvider>().selectSession(sessionId);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to create session: $e';
          });
        }
        return;
      }
    }
    
    _sendSubscription?.cancel();
    _sendSubscription = _provider!.sendMessageStream(text, attachments: attachments).listen(
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
            content: Text('Error: $error'),
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Retry',
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
              title: const Text('Camera'),
              onTap: () { Navigator.pop(ctx); _pickFromCamera(); },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Gallery'),
              onTap: () { Navigator.pop(ctx); _pickFromGallery(); },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('File'),
              onTap: () { Navigator.pop(ctx); _pickFile(); },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.camera);
    if (xfile != null) setState(() => _pendingAttachments.add(File(xfile.path)));
  }

  Future<void> _pickFromGallery() async {
    final xfile = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (xfile != null) setState(() => _pendingAttachments.add(File(xfile.path)));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      setState(() => _pendingAttachments.add(File(result.files.single.path!)));
    }
  }

  String _guessMime(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'pdf' => 'application/pdf',
      'txt' || 'md' => 'text/plain',
      'json' => 'application/json',
      'dart' => 'text/x-dart',
      _ => 'application/octet-stream',
    };
  }

  // ── Git status ──────────────────────────────────────────────────────────

  void _fetchGitStatusIfNeeded(String? directory) {
    if (directory == null || directory == _gitStatusDirectory) return;
    _gitStatusDirectory = directory;

    final machine = context.read<MachineStore>().activeMachine;
    final ssh = machine?.ssh;
    if (ssh == null) {
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
    sessionProvider.clearCurrentSession();
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
        const SnackBar(content: Text('Session summarized')),
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
            final mId = m is Map ? (m['id']?.toString() ?? m['name']?.toString() ?? '') : m.toString();
            if (mId.isNotEmpty) models.add({'providerID': provId, 'modelID': mId});
          }
        }
      }

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No models available')),
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
                  width: 32, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Select Model', style: theme.textTheme.titleMedium),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: const Text('Default (server)'),
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
                                ? Icon(Icons.check, color: theme.colorScheme.primary, size: 20)
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
          SnackBar(content: Text('Failed to load models: $e')),
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
              child: Text('Session Todos',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            if (todos.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Text('No todos in this session'),
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
                        status == 'completed' ? Icons.check_circle
                            : status == 'in_progress' ? Icons.play_circle
                            : Icons.circle_outlined,
                        color: status == 'completed' ? Colors.green
                            : status == 'in_progress' ? Colors.orange
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
          SnackBar(content: Text('Share link: $share')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Share created (check session info)')),
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
        const SnackBar(content: Text('No session info available')),
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
              Text('Session Info', style: Theme.of(ctx).textTheme.titleMedium),
              const Divider(),
              _infoRow('Model', _formatModel(info)),
              _infoRow('Agent', info['agent'] ?? 'default'),
              if (info['cost'] != null) _infoRow('Cost', '\$${info['cost']}'),
              if (info['tokens'] != null) _infoRow('Tokens', _formatTokens(info['tokens'])),
              if (info['directory'] != null) _infoRow('Directory', info['directory']),
              if (info['parentID'] != null) _infoRow('Parent', info['parentID']),
              if (info['share'] != null) _infoRow('Share', '${info['share']}'),
              _infoRow('ID', info['id'] ?? '-'),
              if (children.isNotEmpty) ...[
                const Divider(),
                Text('Child Sessions (${children.length})',
                    style: Theme.of(ctx).textTheme.labelLarge),
                ...children.take(5).map((c) {
                  final title = c is Map ? (c['title'] ?? c['id'] ?? '-') : '$c';
                  return Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text('- $title', style: const TextStyle(fontSize: 13)),
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

  String _formatTokens(dynamic tokens) {
    if (tokens is Map) {
      final input = tokens['input'] ?? 0;
      final output = tokens['output'] ?? 0;
      final reasoning = tokens['reasoning'] ?? 0;
      final cache = tokens['cache'];
      final cacheRead = cache is Map ? (cache['read'] ?? 0) : 0;
      final parts = <String>['in: $input', 'out: $output'];
      if (reasoning != 0) parts.add('reason: $reasoning');
      if (cacheRead != 0) parts.add('cache: $cacheRead');
      return parts.join(', ');
    }
    return '$tokens';
  }

  Widget _infoRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text('$value', style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  // ── Autocomplete logic ──────────────────────────────────────────────────

  void _onTextChanged() {
    final text = _textController.text;
    final cursor = _textController.selection.baseOffset;
    if (cursor < 0) {
      _dismissOverlay();
      return;
    }

    // Slash trigger: text starts with "/" and cursor is still in the command word
    if (text.startsWith('/')) {
      final afterSlash = text.substring(1, cursor.clamp(1, text.length));
      if (!afterSlash.contains(' ')) {
        _acTrigger = '/';
        _acTriggerOffset = 0;
        _fetchSlashSuggestions(afterSlash);
        return;
      }
    }

    // At trigger: find the last "@" before the cursor with no space between it and cursor
    final textBeforeCursor = text.substring(0, cursor.clamp(0, text.length));
    final atIdx = textBeforeCursor.lastIndexOf('@');
    if (atIdx >= 0) {
      final query = textBeforeCursor.substring(atIdx + 1);
      if (!query.contains(' ')) {
        _acTrigger = '@';
        _acTriggerOffset = atIdx;
        _fetchFileSuggestions(query);
        return;
      }
    }

    _dismissOverlay();
  }

  Future<void> _fetchSlashSuggestions(String prefix) async {
    if (_provider == null) return;
    _cachedCommands ??= await _provider!.client.getCommands();
    final cmds = _cachedCommands!;
    final filtered = prefix.isEmpty
        ? cmds
        : cmds.where((c) {
            final name = (c is Map ? c['name'] : '$c') as String? ?? '';
            return name.toLowerCase().startsWith(prefix.toLowerCase());
          }).toList();

    final suggestions = filtered.map((c) {
      final name = c is Map ? c['name'] as String? ?? '' : '$c';
      final desc = c is Map ? c['description'] as String? : null;
      return AutocompleteSuggestion(
        icon: Icons.terminal,
        title: '/$name',
        subtitle: desc,
        insertText: '/$name ',
      );
    }).toList();

    _showSuggestions(suggestions);
  }

  Future<void> _fetchFileSuggestions(String query) async {
    if (_provider == null) return;
    final seq = ++_acDebounceSeq;
    // Debounce: wait 200ms before hitting the server
    await Future.delayed(const Duration(milliseconds: 200));
    if (seq != _acDebounceSeq || !mounted) return;

    try {
      final files = await _provider!.client.findFiles(
        query,
        limit: 15,
        directory: _provider!.directory,
      );
      if (seq != _acDebounceSeq || !mounted) return;

      final suggestions = files.map((path) {
        final isDir = path.endsWith('/');
        return AutocompleteSuggestion(
          icon: isDir ? Icons.folder : Icons.insert_drive_file,
          title: path,
          insertText: '@$path ',
        );
      }).toList();

      _showSuggestions(suggestions);
    } catch (_) {
      _dismissOverlay();
    }
  }

  void _showSuggestions(List<AutocompleteSuggestion> suggestions) {
    if (!mounted) return;
    _acSuggestions = suggestions;
    _acHighlight = suggestions.isNotEmpty ? 0 : -1;
    if (suggestions.isEmpty) {
      _dismissOverlay();
      return;
    }
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    } else {
      _overlayEntry = OverlayEntry(
        builder: (_) => Positioned(
          width: 340,
          child: CompositedTransformFollower(
            link: _inputLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, -8),
            followerAnchor: Alignment.bottomLeft,
            targetAnchor: Alignment.topLeft,
            child: _buildOverlayContent(),
          ),
        ),
      );
      Overlay.of(context).insert(_overlayEntry!);
    }
  }

  Widget _buildOverlayContent() {
    return AutocompleteOverlay(
      suggestions: _acSuggestions,
      highlightIndex: _acHighlight,
      onSelect: _onSuggestionSelected,
    );
  }

  void _onSuggestionSelected(AutocompleteSuggestion s) {
    final text = _textController.text;
    if (_acTrigger == '/') {
      _textController.text = s.insertText;
      _textController.selection = TextSelection.collapsed(offset: s.insertText.length);
    } else {
      final before = text.substring(0, _acTriggerOffset);
      final afterCursor = _textController.selection.baseOffset < text.length
          ? text.substring(_textController.selection.baseOffset)
          : '';
      final newText = '$before${s.insertText}$afterCursor';
      _textController.text = newText;
      _textController.selection = TextSelection.collapsed(
        offset: before.length + s.insertText.length,
      );
    }
    _dismissOverlay();
  }

  void _dismissOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (_acSuggestions.isNotEmpty) {
      setState(() {
        _acSuggestions = [];
        _acHighlight = -1;
        _acTrigger = '';
      });
    }
  }

  /// Handles slash commands typed in the input (e.g. /compact, /model).
  bool _handleSlashCommand(String text) {
    if (!text.startsWith('/') || _provider == null || _provider!.currentSessionId == null) {
      return false;
    }
    final parts = text.split(RegExp(r'\s+'));
    final command = parts[0].substring(1);
    final args = parts.length > 1 ? parts.sublist(1).join(' ') : null;

    _provider!.client.executeCommand(
      _provider!.currentSessionId!,
      command,
      arguments: args,
    ).then((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Command /$command executed')),
        );
      }
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Command failed: $e')),
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
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
              onPressed: _currentSearchMatch > 0
                  ? () => _navigateSearch(-1)
                  : null,
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
                      const PopupMenuItem(
                        value: 'todos',
                        child: ListTile(
                          leading: Icon(Icons.checklist),
                          title: Text('Todos'),
                          dense: true, contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: ListTile(
                          leading: Icon(Icons.share),
                          title: Text('Share'),
                          dense: true, contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'info',
                        child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('Session Info'),
                          dense: true, contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'summarize',
                        child: ListTile(
                          leading: Icon(Icons.summarize),
                          title: Text('Summarize'),
                          dense: true, contentPadding: EdgeInsets.zero,
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
      decoration: const InputDecoration(
        hintText: 'Search in chat...',
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
    if (_currentSearchMatch < 0 || _currentSearchMatch >= _searchMatchIndices.length) return;
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing chat...'),
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
              Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/settings'),
                icon: const Icon(Icons.settings),
                label: const Text('Go to Settings'),
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
                content: Text(lastError, maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
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
                      child: const Text('Retry'),
                    ),
                  TextButton(
                    onPressed: () => _provider!.clearError(),
                    child: const Text('Dismiss'),
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
                          return DateHeader(date: item.date!);
                        }
                        return _buildMessageBubble(
                          item.message!,
                          item.historyIndex!,
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    _TypingDots(),
                    const SizedBox(width: 8),
                    Text('Generating...', style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
                  ],
                ),
              ),

            ChatPermissionArea(
              pendingPermissions: pendingPerms,
              pendingQuestions: pendingQs,
              onPermissionReply: (id, reply) => _provider!.replyToPermission(id, reply),
              onQuestionReply: (id, answers) => _provider!.replyToQuestion(id, answers),
              onQuestionReject: (id) => _provider!.rejectQuestion(id),
            ),

            if (isStreaming)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: TextButton.icon(
                  onPressed: () => _provider!.abortSession(),
                  icon: const Icon(Icons.stop_circle_outlined, size: 20),
                  label: const Text('Stop'),
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
            'Como posso ajudar?',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Envie uma mensagem para começar',
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
      toolCalls = _provider!.getToolCallsForMessage(messageId)
          .where((tc) => !_qaHiddenTools.contains(tc.name.toLowerCase()))
          .toList();
      shellCommands = _provider!.getShellCommandsForMessage(messageId);
      fileChanges = _provider!.getFileChangesForMessage(messageId);
      answeredQuestions = _provider!.getAnsweredQuestionsForMessage(messageId);
    }

    final showThinking = context.read<SettingsProvider>().showThinking;
    if (!showThinking) reasoning = null;

    final isLastMessage = index == _provider!.history.length - 1;
    final isActivelyStreaming = !isUser && _provider!.isStreaming && isLastMessage;

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
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: message.text ?? ''));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied'),
                      duration: Duration(seconds: 1)),
                );
              },
            ),
            if (!isUser && messageId != null) ...[
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('Revert changes'),
                subtitle: const Text('Undo file changes from this message'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final ok = await _provider!.revertMessage(messageId);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(ok ? 'Reverted' : 'Revert failed')),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.fork_right),
                title: const Text('Fork from here'),
                subtitle: const Text('Branch into a new session'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final newId = await _provider!.forkSession(messageId);
                  if (newId != null && mounted) {
                    await context.read<SessionProvider>().selectSession(newId);
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
      layerLink: _inputLayerLink,
      voiceService: _voiceService,
      pendingAttachments: _pendingAttachments,
      onSend: _sendMessage,
      onAttach: _showAttachmentPicker,
      onVoiceResult: _sendVoiceText,
      onRemoveAttachment: (i) => setState(() => _pendingAttachments.removeAt(i)),
      guessMime: _guessMime,
    );
  }
}

class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
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
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
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
