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
import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import '../services/voice_service.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/date_header.dart';
import '../widgets/chat_permission_area.dart';
import '../models/file_change.dart';
import '../models/message_part.dart';
import '../widgets/autocomplete_overlay.dart';
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
  final Set<int> _expandedReasoningIndices = {};
  final List<File> _pendingAttachments = [];
  bool _showScrollToBottom = false;
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
      setState(() {
        _isLoading = false;
        _error = 'Server not configured. Please go to Settings.';
      });
      return;
    }

    if (provider.clientOrNull != clientProvider.client) {
      provider.updateClient(clientProvider.client!);
    }

    final sessionProvider = context.read<SessionProvider>();
    if (sessionProvider.currentSessionId == null) {
      await sessionProvider.loadPersistedSession();
    }
    if (!mounted) return;

    final sessionId = sessionProvider.currentSessionId;
    if (sessionId != null && sessionId != provider.currentSessionId) {
      await provider.switchSession(sessionId);
    }

    // Reset cached chat items when entering a new session
    _cachedChatItems = null;
    _cachedHistoryLength = -1;

    setState(() {
      _provider = provider;
      _isLoading = false;
    });
  }

  Future<void> _createSession() async {
    if (_provider == null) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      await _provider!.createSession();
      final sessionId = _provider!.currentSessionId;
      if (sessionId != null && mounted) {
        await context.read<SessionProvider>().selectSession(sessionId);
      }
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to create session: $e';
        _isLoading = false;
      });
    }
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

  // ── Menu actions ────────────────────────────────────────────────────────

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
      final providers = await _provider!.client.getProviders();
      if (!mounted) return;

      final allRaw = providers['all'];
      final allList = allRaw is List ? allRaw : <dynamic>[];
      final models = <Map<String, String>>[];
      for (final prov in allList) {
        if (prov is! Map) continue;
        final provId = prov['id']?.toString() ?? '';
        final provModels = prov['models'] as Map<String, dynamic>? ?? {};
        for (final mId in provModels.keys) {
          models.add({'providerID': provId, 'modelID': mId});
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

      await showModalBottomSheet(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Select Model',
                    style: Theme.of(ctx).textTheme.titleMedium),
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Default (server)'),
                trailing: current == null ? const Icon(Icons.check) : null,
                onTap: () {
                  _provider!.modelOverride = null;
                  Navigator.pop(ctx);
                },
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: models.length,
                  itemBuilder: (_, i) {
                    final m = models[i];
                    final isSelected = current != null &&
                        current['providerID'] == m['providerID'] &&
                        current['modelID'] == m['modelID'];
                    return ListTile(
                      title: Text(m['modelID']!),
                      subtitle: Text(m['providerID']!),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () {
                        _provider!.modelOverride = m;
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
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
    if (_cachedChatItems != null && _cachedHistoryLength == currentLength) {
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

    final sessionProvider = context.watch<SessionProvider>();
    final currentSession = sessionProvider.currentSessionId != null
        ? sessionProvider.findSession(sessionProvider.currentSessionId!)
        : null;

    // Session info subtitle
    String? subtitle;
    if (_provider != null) {
      final info = _provider!.sessionInfo;
      if (info != null) {
        final rawModel = info['model'];
      final model = info['modelID'] as String?
          ?? (rawModel is Map ? rawModel['id']?.toString() : rawModel?.toString());
        if (model != null) subtitle = model;
      }
      final override = _provider!.modelOverride;
      if (override != null) {
        subtitle = '${override['modelID'] ?? ''} (override)';
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? _buildChatSearchField()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentSession?.displayName ?? 'PAI Chat',
                    style: const TextStyle(fontSize: 16),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        leading: IconButton(
          icon: Icon(_isSearching ? Icons.close : Icons.arrow_back),
          onPressed: _isSearching
              ? () => setState(() {
                    _isSearching = false;
                    _chatSearchController.clear();
                    _searchMatchIndices = [];
                    _currentSearchMatch = -1;
                  })
              : () => Navigator.pushReplacementNamed(context, '/sessions'),
        ),
        actions: [
          if (!_isSearching)
            IconButton(
              icon: const Icon(Icons.search),
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
          if (_provider != null && !_isSearching)
            AnimatedBuilder(
              animation: _provider!,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ConnectionStatusIndicator(
                      state: _provider!.connectionState,
                      onReconnect: () => _provider?.reconnect(),
                      compact: true,
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) => _handleMenuAction(value),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'model',
                          child: ListTile(
                            leading: Icon(Icons.auto_awesome),
                            title: Text('Change Model'),
                            dense: true, contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'todos',
                          child: ListTile(
                            leading: Icon(Icons.checklist),
                            title: Text('View Todos'),
                            dense: true, contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'share',
                          child: ListTile(
                            leading: Icon(Icons.share),
                            title: Text('Share Session'),
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
                    ),
                  ],
                );
              },
            ),
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
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('No session selected'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _createSession,
              icon: const Icon(Icons.add),
              label: const Text('Start New Chat'),
            ),
          ],
        ),
      );
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
                      onPressed: () {
                        _provider!.clearError();
                        _provider!.loadHistory();
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
    if (!isUser && messageId != null) {
      reasoning = _provider!.getReasoningForHistoryIndex(index);
      toolCalls = _provider!.getToolCallsForMessage(messageId)
          .where((tc) => !_qaHiddenTools.contains(tc.name.toLowerCase()))
          .toList();
      shellCommands = _provider!.getShellCommandsForMessage(messageId);
      fileChanges = _provider!.getFileChangesForMessage(messageId);
    }

    final isLastMessage = index == _provider!.history.length - 1;
    final isActivelyStreaming = !isUser && _provider!.isStreaming && isLastMessage;

    return ChatMessageTile(
      message: message,
      historyIndex: index,
      displayText: _buildDisplayText(message, index),
      timestamp: timestamp,
      reasoning: reasoning,
      isReasoningExpanded: _expandedReasoningIndices.contains(index),
      onToggleReasoning: () {
        setState(() {
          if (_expandedReasoningIndices.contains(index)) {
            _expandedReasoningIndices.remove(index);
          } else {
            _expandedReasoningIndices.add(index);
          }
        });
      },
      onLongPress: () => _showMessageActions(message, index),
      isStreaming: isActivelyStreaming,
      markdownStyleSheet: _cachedMarkdownStyleSheet,
      toolCalls: toolCalls,
      shellCommands: shellCommands,
      fileChanges: fileChanges,
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
    final text = message.text ?? '';
    if (message.origin != MessageOrigin.llm || _provider == null) return text;

    final messageId = _provider!.getMessageIdAt(index);
    if (messageId == null) return text;

    // Only Q&A inline inserts remain — tool calls and shell commands
    // are rendered as rich widgets via ChatMessageTile
    final inserts = <(int, String, int)>[];
    int seq = 0;

    for (final aq in _provider!.getAnsweredQuestionsForMessage(messageId)) {
      final q = aq.request.questions
          .map((q) => q.question).where((q) => q.isNotEmpty).join(' / ');
      final a = aq.answers
          .where((a) => a.isNotEmpty).map((a) => a.join(', ')).join(' | ');
      inserts.add((aq.textInsertOffset, '\n\n`$q`\n`> $a`\n\n', seq++));
    }

    if (inserts.isEmpty) return text;

    // Sort descending by offset (insert from end to start).
    // For equal offsets, sort descending by seq so the earliest item
    // is inserted last and ends up on top (chronological order).
    inserts.sort((a, b) {
      final cmp = b.$1.compareTo(a.$1);
      if (cmp != 0) return cmp;
      return b.$3.compareTo(a.$3);
    });
    var result = text;
    for (final (offset, block, _) in inserts) {
      final pos = offset.clamp(0, result.length);
      result = result.substring(0, pos) + block + result.substring(pos);
    }
    return result;
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
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
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
