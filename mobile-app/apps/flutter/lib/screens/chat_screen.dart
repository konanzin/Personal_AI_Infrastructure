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
import '../widgets/shell_command_bubble.dart';
import '../widgets/tool_call_bubble.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: Text(currentSession?.displayName ?? 'PAI Chat'),
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
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: ConnectionStatusIndicator(
                    state: _provider!.connectionState,
                    onReconnect: () => _provider?.reconnect(),
                    compact: true,
                  ),
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

        return Column(
          children: [
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
            Clipboard.setData(ClipboardData(text: message.text ?? ''));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message copied'),
                duration: Duration(seconds: 2),
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
                        key: ValueKey('md-${message.text?.hashCode ?? 0}'),
                        data: message.text ?? '',
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
              
              // Tool call bubbles for assistant messages
              if (!isUser && _provider != null)
                ..._buildToolCallBubbles(index),
              
              // Shell command bubbles for assistant messages
              if (!isUser && _provider != null)
                ..._buildShellCommandBubbles(index),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds tool call bubbles for a message at the given index.
  /// Returns an empty list if no tool calls are associated.
  List<Widget> _buildToolCallBubbles(int messageIndex) {
    final messageId = _provider!.getMessageIdAt(messageIndex);
    if (messageId == null) return const [];
    
    final toolCalls = _provider!.getToolCallsForMessage(messageId);
    if (toolCalls.isEmpty) return const [];
    
    return toolCalls.map((toolCall) => ToolCallBubble(toolCall: toolCall)).toList();
  }

  /// Builds shell command bubbles for a message at the given index.
  /// Returns an empty list if no shell commands are associated.
  List<Widget> _buildShellCommandBubbles(int messageIndex) {
    final messageId = _provider!.getMessageIdAt(messageIndex);
    if (messageId == null) return const [];
    
    final shells = _provider!.getShellCommandsForMessage(messageId);
    if (shells.isEmpty) return const [];
    
    return shells.map((shell) => ShellCommandBubble(shell: shell)).toList();
  }

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
