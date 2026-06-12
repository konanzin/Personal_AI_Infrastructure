import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/chat_message.dart';
import '../models/file_change.dart';
import '../models/message_part.dart';
import 'code_block_widget.dart';
import 'file_diff_card.dart';
import 'reasoning_message_bubble.dart';
import 'shell_command_bubble.dart';
import 'tool_call_bubble.dart';
import '../providers/opencode_provider.dart';
import '../theme.dart';
import '../l10n/app_localizations.dart';

/// One renderable slice of an agent message: either markdown prose or the
/// body of a fenced code block.
@visibleForTesting
class MarkdownSegment {
  final String text;
  final bool isCode;
  final String language;

  const MarkdownSegment.text(this.text)
      : isCode = false,
        language = '';
  const MarkdownSegment.code(this.text, this.language) : isCode = true;
}

/// Splits message text into prose and fenced-code segments so code blocks
/// can be rendered by [CodeBlockWidget] directly. flutter_markdown's custom
/// 'pre' builders leave a dangling inline element behind (its `visitText`
/// returns null), tripping the `_inlines.isEmpty` assert on every fenced
/// block — bypassing it for fences avoids that entirely.
/// An unclosed trailing fence (mid-stream) becomes a code segment.
@visibleForTesting
List<MarkdownSegment> splitFencedCodeBlocks(String text) {
  final segments = <MarkdownSegment>[];
  final prose = StringBuffer();
  final code = StringBuffer();
  String language = '';
  var inFence = false;

  void flushProse() {
    final t = prose.toString();
    if (t.trim().isNotEmpty) segments.add(MarkdownSegment.text(t));
    prose.clear();
  }

  void flushCode() {
    segments.add(MarkdownSegment.code(code.toString(), language));
    code.clear();
    language = '';
  }

  final lines = text.split('\n');
  for (final line in lines) {
    final fenceMatch = RegExp(r'^ {0,3}```\s*([^\s`]*)\s*$').firstMatch(line);
    if (fenceMatch != null) {
      if (inFence) {
        flushCode();
      } else {
        flushProse();
        language = fenceMatch.group(1) ?? '';
      }
      inFence = !inFence;
      continue;
    }
    final target = inFence ? code : prose;
    if (target.isNotEmpty) target.write('\n');
    target.write(line);
  }
  if (inFence) {
    flushCode();
  } else {
    flushProse();
  }
  return segments;
}

/// Trims incomplete markdown tokens from the end of streaming text so that
/// partial syntax like `**word` doesn't flash as raw text before closing.
String _sanitizeStreamingMarkdown(String text) {
  if (text.isEmpty) return text;

  // Find the last newline — only analyze the last line for trailing tokens.
  final lastNl = text.lastIndexOf('\n');
  final tail = lastNl >= 0 ? text.substring(lastNl + 1) : text;
  final head = lastNl >= 0 ? text.substring(0, lastNl + 1) : '';

  // Check for unclosed fenced code block (odd number of ```)
  final fenceMatches = RegExp(r'```').allMatches(text);
  if (fenceMatches.length.isOdd) {
    // Inside a code block — render everything up to the opening fence as-is,
    // and append the code block content as plain preformatted text.
    return text;
  }

  // Check for unclosed inline markers in the tail.
  var safeTail = tail;

  // Bold/italic: count unmatched ** or * at the end
  final lastDoubleStar = safeTail.lastIndexOf('**');
  if (lastDoubleStar >= 0) {
    final after = safeTail.substring(lastDoubleStar + 2);
    // If there's no closing ** after the last opening **, trim there
    if (!after.contains('**')) {
      safeTail = safeTail.substring(0, lastDoubleStar);
    }
  } else {
    // Single * (italic)
    final stars = '*'.allMatches(safeTail).length;
    if (stars.isOdd) {
      final lastStar = safeTail.lastIndexOf('*');
      safeTail = safeTail.substring(0, lastStar);
    }
  }

  // Unclosed inline code backtick
  final backticks = '`'.allMatches(safeTail).length;
  if (backticks.isOdd) {
    final lastBt = safeTail.lastIndexOf('`');
    safeTail = safeTail.substring(0, lastBt);
  }

  // Unclosed link: [ without ]
  final lastBracket = safeTail.lastIndexOf('[');
  if (lastBracket >= 0 && !safeTail.substring(lastBracket).contains(']')) {
    safeTail = safeTail.substring(0, lastBracket);
  }

  return head + safeTail;
}

/// Self-contained widget for a single chat message.
/// User messages render as a colored bubble (right-aligned).
/// Agent messages render as plain markdown content (left-aligned, no bubble).
class ChatMessageTile extends StatelessWidget {
  final ChatMessage message;
  final int historyIndex;
  final String displayText;
  final DateTime? timestamp;
  final String? reasoning;
  final VoidCallback? onLongPress;
  final VoidCallback? onRegenerate;
  final bool isStreaming;
  final MarkdownStyleSheet? markdownStyleSheet;
  final List<ToolCallPart> toolCalls;
  final List<ShellPart> shellCommands;
  final List<FileChange> fileChanges;
  final List<AnsweredQuestionData> answeredQuestions;

  const ChatMessageTile({
    super.key,
    required this.message,
    required this.historyIndex,
    required this.displayText,
    this.timestamp,
    this.reasoning,
    this.onLongPress,
    this.onRegenerate,
    this.isStreaming = false,
    this.markdownStyleSheet,
    this.toolCalls = const [],
    this.shellCommands = const [],
    this.fileChanges = const [],
    this.answeredQuestions = const [],
  });

  /// Footer copy is shown only for plain-text answers (no tool activity).
  bool get _showFooterCopy =>
      displayText.isNotEmpty &&
      toolCalls.isEmpty &&
      shellCommands.isEmpty &&
      fileChanges.isEmpty;

  @override
  Widget build(BuildContext context) {
    final isUser = message.origin == MessageOrigin.user;
    final theme = Theme.of(context);

    if (isUser) {
      return _buildUserBubble(context, theme);
    }
    return _buildAgentMessage(context, theme);
  }

  Widget _buildUserBubble(BuildContext context, ThemeData theme) {
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(20).copyWith(
                    bottomRight: const Radius.circular(4),
                  ),
                ),
                child: Text(
                  message.text ?? '',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 16,
                  ),
                ),
              ),
              if (timestamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, right: 8),
                  child: Text(
                    _formatTime(timestamp!),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAgentMessage(BuildContext context, ThemeData theme) {
    return RepaintBoundary(
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (toolCalls.isNotEmpty || shellCommands.isNotEmpty || fileChanges.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
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
              if (answeredQuestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final aq in answeredQuestions)
                        _AnsweredQuestionBubble(data: aq),
                    ],
                  ),
                ),
              if (reasoning != null && reasoning!.isNotEmpty)
                ReasoningMessageBubble(reasoning: reasoning!),
              if (displayText.isNotEmpty)
                Column(
                  key: ValueKey('md-$historyIndex-${isStreaming ? displayText.length : 0}'),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final segment in splitFencedCodeBlocks(isStreaming
                        ? _sanitizeStreamingMarkdown(displayText)
                        : displayText))
                      if (segment.isCode)
                        CodeBlockWidget(
                          code: segment.text,
                          language: segment.language,
                        )
                      else
                        MarkdownBody(
                          data: segment.text,
                          selectable: !isStreaming,
                          onTapLink: (text, href, title) {
                            if (href != null) {
                              launchUrl(Uri.parse(href),
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          styleSheet: markdownStyleSheet,
                        ),
                  ],
                ),
              if (timestamp != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _formatTime(timestamp!),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              // The footer copy button is only for plain text answers. On
              // messages that carry tool calls / shell / file changes it reads
              // as "copy this tool call", which is confusing — there, copy
              // lives inside each tool call's expanded view instead. Long-press
              // (message actions) and selectable text still copy the answer.
              // The undo/regenerate action stays available regardless.
              if (!isStreaming && (_showFooterCopy || onRegenerate != null))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_showFooterCopy)
                        _ActionIconButton(
                          icon: Icons.content_copy,
                          tooltip: AppLocalizations.of(context)!.copy,
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: displayText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      AppLocalizations.of(context)!.copied),
                                  duration: const Duration(seconds: 1)),
                            );
                          },
                        ),
                      if (onRegenerate != null)
                        _ActionIconButton(
                          icon: Icons.undo,
                          tooltip: AppLocalizations.of(context)!.undo,
                          onTap: onRegenerate!,
                        ),
                    ],
                  ),
                ),
            ],
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

class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _AnsweredQuestionBubble extends StatefulWidget {
  final AnsweredQuestionData data;
  const _AnsweredQuestionBubble({required this.data});

  @override
  State<_AnsweredQuestionBubble> createState() => _AnsweredQuestionBubbleState();
}

class _AnsweredQuestionBubbleState extends State<_AnsweredQuestionBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final questions = widget.data.request.questions;
    final answers = widget.data.answers;

    final questionText = questions
        .map((q) => q.question)
        .where((q) => q.isNotEmpty)
        .join(' / ');
    final answerText = answers
        .where((a) => a.isNotEmpty)
        .map((a) => a.join(', '))
        .join(' | ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 14, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.question,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context)!.answered,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.semanticColors.success,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(top: 4, left: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(color: theme.colorScheme.primary.withAlpha(80), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    questionText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '→ $answerText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
