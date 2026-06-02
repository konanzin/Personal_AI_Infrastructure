import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:provider/provider.dart';

import '../providers/opencode_provider.dart';
import '../providers/session_provider.dart';
import '../services/opencode_client.dart';
import '../services/secure_storage.dart';
import '../services/voice_service.dart';
import '../widgets/code_block_widget.dart';
import '../widgets/connection_status_indicator.dart';
import '../widgets/date_header.dart';
import '../widgets/permission_card.dart';
import '../widgets/question_card.dart';
import '../widgets/reasoning_message_bubble.dart';
import '../models/message_part.dart';
import '../widgets/voice_fab.dart';

// ── Chat list item helper ────────────────────────────────────────────────

/// Represents a single entry in the rendered chat list.
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

// ── Markdown code-block builder ──────────────────────────────────────────

/// Intercepts `<pre>` elements from [MarkdownBody] and renders them
/// with syntax highlighting via [CodeBlockWidget]. Inline `<code>`
/// (without a `<pre>` parent) continues to use the default styling.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // Extract language from <code class="language-xxx">
    String language = '';
    for (final child in element.children ?? []) {
      if (child is md.Element && child.tag == 'code') {
        final classAttr = child.attributes['class'] ?? '';
        if (classAttr.startsWith('language-')) {
          language = classAttr.substring(9);
        }
        break;
      }
    }

    return CodeBlockWidget(
      code: element.textContent,
      language: language,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  OpenCodeProvider? _provider;
  bool _isLoading = true;
  String? _error;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final VoiceService _voiceService = VoiceService();
  final Set<int> _expandedReasoningIndices = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  @override
  void dispose() {
    _provider?.dispose();
    _voiceService.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _initializeChat() async {
    final sessionProvider = context.read<SessionProvider>();
    if (sessionProvider.currentSessionId == null) {
      await sessionProvider.loadPersistedSession();
    }
    if (!mounted) return;
    
    final credentials = await SecureStorageService.loadCredentials();
    if (!mounted) return;
    final serverUrl = credentials['serverUrl'];
    final username = credentials['username'];
    final password = credentials['password'];
    
    if (serverUrl == null || username == null || password == null) {
      setState(() {
        _isLoading = false;
        _error = 'Server not configured. Please go to Settings.';
      });
      return;
    }

    final client = OpenCodeClient(
      ClientConfig(
        baseUrl: serverUrl,
        username: username,
        password: password,
      ),
    );

    final sessionId = sessionProvider.currentSessionId;
    
    setState(() {
      _provider = OpenCodeProvider(
        client: client,
        sessionId: sessionId,
      );
    });
    
    if (sessionId != null && _provider != null) {
      await _provider!.loadHistory();
    }
    
    setState(() {
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
    
    _textController.clear();
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
    
    // Escuta o stream de forma não-bloqueante para permitir rebuilds da UI
    _provider!.sendMessageStream(text).listen(
      (chunk) {
        debugPrint('[PAI_SSE] ChatScreen received chunk: "${chunk.substring(0, chunk.length > 30 ? 30 : chunk.length)}..."');
        // A UI já é atualizada pelo notifyListeners() no provider
      },
      onDone: () {
        // Scroll to latest message after response completes
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
        debugPrint('Error in message stream: $error');
      },
    );
  }

  Future<void> _sendVoiceText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _textController.text = trimmed;
    await _sendMessage();
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
              if (info['share'] != null) _infoRow('Share', '${info['share']}'),
              _infoRow('ID', info['id'] ?? '-'),
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

    final items = <_ChatListItem>[];
    DateTime? lastDate;

    // Walk oldest → newest so headers appear before the first message of each date.
    for (int i = 0; i < _provider!.history.length; i++) {
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

    // Reverse: newest first → index 0 sits at the bottom with reverse:true.
    return items.reversed.toList();
  }

  @override
  Widget build(BuildContext context) {
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
        title: Column(
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
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pushReplacementNamed(context, '/sessions'),
        ),
        actions: [
          if (_provider != null)
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
            // Error banner
            if (lastError != null)
              MaterialBanner(
                content: Text(lastError, maxLines: 2, overflow: TextOverflow.ellipsis),
                leading: Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                actions: [
                  TextButton(
                    onPressed: () => _provider!.clearError(),
                    child: const Text('Dismiss'),
                  ),
                ],
              ),

            // Messages
            Expanded(
              child: ListView.builder(
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
            ),

            // Pending permissions and questions (inline)
            if (pendingPerms.isNotEmpty || pendingQs.isNotEmpty)
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...pendingPerms.map((req) => PermissionCard(
                        request: req,
                        onReply: (reply) => _provider!.replyToPermission(req.id, reply),
                      )),
                      ...pendingQs.map((req) => QuestionCard(
                        request: req,
                        onReply: (answers) => _provider!.replyToQuestion(req.id, answers),
                        onReject: () => _provider!.rejectQuestion(req.id),
                      )),
                    ],
                  ),
                ),
              ),

            // Stop button (visible during streaming)
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

            // Input
            _buildInput(),
          ],
        );
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index) {
    final isUser = message.origin == MessageOrigin.user;
    final theme = Theme.of(context);
    
    // Get timestamp from provider's server data
    DateTime? timestamp;
    if (_provider != null) {
      final messageId = _provider!.getMessageIdAt(index);
      if (messageId != null) {
        timestamp = _provider!.getMessageTimestamp(messageId);
      }
    }
    
    // Get reasoning for this message if it's from agent
    String? reasoning;
    if (!isUser) {
      reasoning = _provider!.getReasoningForHistoryIndex(index);
    }
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: GestureDetector(
          onLongPress: () {
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
                          const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
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
                              SnackBar(content: Text(ok ? 'Reverted' : 'Revert failed')),
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
          },
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isUser 
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20).copyWith(
                    bottomRight: isUser ? const Radius.circular(4) : null,
                    bottomLeft: !isUser ? const Radius.circular(4) : null,
                  ),
                ),
                child: isUser
                    ? Text(
                        message.text ?? '',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 16,
                        ),
                      )
                    : MarkdownBody(
                        key: ValueKey('md-${_buildDisplayText(message, index).hashCode}'),
                        data: _buildDisplayText(message, index),
                        builders: {
                          'pre': _CodeBlockBuilder(),
                        },
                        styleSheet: MarkdownStyleSheet(
                          p: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          strong: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          em: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                          code: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 14,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          ),
                          codeblockDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          listBullet: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 16,
                          ),
                          h1: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          h3: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                          blockquote: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 16,
                            fontStyle: FontStyle.italic,
                          ),
                          blockquoteDecoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
              ),
              
              // Timestamp
              if (timestamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                  child: Text(
                    _formatTime(timestamp),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              // Inline reasoning expand/collapse
              if (!isUser && reasoning != null && reasoning.isNotEmpty)
                ReasoningMessageBubble(
                  reasoning: reasoning,
                  isExpanded: _expandedReasoningIndices.contains(index),
                  onToggle: () {
                    setState(() {
                      if (_expandedReasoningIndices.contains(index)) {
                        _expandedReasoningIndices.remove(index);
                      } else {
                        _expandedReasoningIndices.add(index);
                      }
                    });
                  },
                ),
              
              // Tool calls and shell commands are rendered inline via _buildDisplayText
            ],
          ),
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

    // Collect all inline inserts: (offset, formattedBlock, chronologicalOrder)
    final inserts = <(int, String, int)>[];
    int seq = 0;

    // Answered questions
    for (final aq in _provider!.getAnsweredQuestionsForMessage(messageId)) {
      final q = aq.request.questions
          .map((q) => q.question).where((q) => q.isNotEmpty).join(' / ');
      final a = aq.answers
          .where((a) => a.isNotEmpty).map((a) => a.join(', ')).join(' | ');
      inserts.add((aq.textInsertOffset, '\n\n`$q`\n`> $a`\n\n', seq++));
    }

    // Tool calls (excluding question-related tools)
    for (final tc in _provider!.getToolCallsForMessage(messageId)) {
      if (_qaHiddenTools.contains(tc.name.toLowerCase())) continue;
      final status = switch (tc.state) {
        ToolCallState.pending => '\u23f3',
        ToolCallState.running => '\u23f3',
        ToolCallState.completed => '\u2713',
        ToolCallState.error => '\u2717 ${tc.errorMessage ?? '?'}',
      };
      final cmd = tc.input['command'] as String? ??
          tc.input['description'] as String?;
      final label = cmd != null
          ? '\$ ${cmd.length > 50 ? '${cmd.substring(0, 47)}...' : cmd}'
          : tc.name;
      inserts.add((tc.textInsertOffset, '\n\n`$label $status`\n\n', seq++));
    }

    // Shell commands
    for (final sh in _provider!.getShellCommandsForMessage(messageId)) {
      final cmd = sh.command.length > 60
          ? '${sh.command.substring(0, 57)}...' : sh.command;
      inserts.add((sh.textInsertOffset, '\n\n`\$ $cmd \u2713`\n\n', seq++));
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

  /// Builds shell command bubbles for a message at the given index.
  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (messageDate == today) {
      return timeStr;
    } else if (messageDate == yesterday) {
      return 'Yesterday $timeStr';
    } else {
      // Mesmo ano não mostra ano
      if (time.year == now.year) {
        final month = _monthName(time.month);
        return '$month ${time.day}, $timeStr';
      } else {
        final month = _monthName(time.month);
        return '$month ${time.day}, ${time.year} $timeStr';
      }
    }
  }

  String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return names[month - 1];
  }

  Widget _buildInput() {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Voice button: STT only, no TTS playback.
            SizedBox(
              width: 76,
              child: VoiceFab(
                voiceService: _voiceService,
                onSpeechResult: (text) {
                  _sendVoiceText(text);
                },
              ),
            ),
            const SizedBox(width: 8),
            
            // Text field
            Expanded(
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: 'Ask me anything...',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                ),
                keyboardType: TextInputType.multiline,
                minLines: 1,
                maxLines: 5,
                onEditingComplete: () {
                  // Prevent Enter from sending - user must tap send button
                  _textController.text += '\n';
                },
              ),
            ),
            
            // Send button
            IconButton(
              onPressed: _sendMessage,
              icon: const Icon(Icons.send),
              color: theme.colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
