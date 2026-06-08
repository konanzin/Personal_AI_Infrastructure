import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../models/file_change.dart';
import '../models/message_part.dart';
import 'code_block_widget.dart';
import 'file_diff_card.dart';
import 'reasoning_message_bubble.dart';
import 'shell_command_bubble.dart';
import 'tool_call_bubble.dart';

class _CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
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
    return CodeBlockWidget(code: element.textContent, language: language);
  }
}

/// Self-contained widget for a single chat message bubble.
/// Wrapped in RepaintBoundary to isolate repaint from siblings.
class ChatMessageTile extends StatelessWidget {
  final ChatMessage message;
  final int historyIndex;
  final String displayText;
  final DateTime? timestamp;
  final String? reasoning;
  final bool isReasoningExpanded;
  final VoidCallback? onToggleReasoning;
  final VoidCallback? onLongPress;
  final bool isStreaming;
  final MarkdownStyleSheet? markdownStyleSheet;
  final List<ToolCallPart> toolCalls;
  final List<ShellPart> shellCommands;
  final List<FileChange> fileChanges;

  const ChatMessageTile({
    super.key,
    required this.message,
    required this.historyIndex,
    required this.displayText,
    this.timestamp,
    this.reasoning,
    this.isReasoningExpanded = false,
    this.onToggleReasoning,
    this.onLongPress,
    this.isStreaming = false,
    this.markdownStyleSheet,
    this.toolCalls = const [],
    this.shellCommands = const [],
    this.fileChanges = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.origin == MessageOrigin.user;
    final theme = Theme.of(context);

    return RepaintBoundary(
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20).copyWith(
                      bottomRight:
                          isUser ? const Radius.circular(4) : null,
                      bottomLeft:
                          !isUser ? const Radius.circular(4) : null,
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
                      : isStreaming
                          ? SelectableText(
                              displayText,
                              style: TextStyle(
                                color: theme.colorScheme.onSurface,
                                fontSize: 16,
                              ),
                            )
                          : MarkdownBody(
                              key: ValueKey('md-$historyIndex'),
                              data: displayText,
                              builders: {'pre': _CodeBlockBuilder()},
                              onTapLink: (text, href, title) {
                                if (href != null) {
                                  launchUrl(Uri.parse(href),
                                      mode: LaunchMode.externalApplication);
                                }
                              },
                              styleSheet: markdownStyleSheet,
                            ),
                ),
                // Tool calls, shell commands, and file changes as rich widgets
                if (!isUser && (toolCalls.isNotEmpty || shellCommands.isNotEmpty || fileChanges.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final tc in toolCalls)
                          ToolCallBubble(toolCall: tc),
                        for (final sh in shellCommands)
                          ShellCommandBubble(shell: sh),
                        for (final fc in fileChanges)
                          FileDiffCard(change: fc),
                      ],
                    ),
                  ),
                if (timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 8, right: 8),
                    child: Text(
                      _formatTime(timestamp!),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (!isUser && reasoning != null && reasoning!.isNotEmpty)
                  ReasoningMessageBubble(
                    reasoning: reasoning!,
                    isExpanded: isReasoningExpanded,
                    onToggle: onToggleReasoning ?? () {},
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatTime(DateTime time) {
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
    } else if (time.year == now.year) {
      return '${_monthName(time.month)} ${time.day}, $timeStr';
    } else {
      return '${_monthName(time.month)} ${time.day}, ${time.year} $timeStr';
    }
  }

  static String _monthName(int month) {
    const names = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return names[month - 1];
  }
}
