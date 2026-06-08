import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/message_part.dart';

/// A compact widget for rendering tool calls in the chat timeline.
///
/// Displays tool call state with color-coded left border accent:
/// - Pending: orange pulse icon
/// - Running: blue spinner
/// - Completed: green check with input/output
/// - Error: red error icon with message
class ToolCallBubble extends StatelessWidget {
  final ToolCallPart toolCall;

  const ToolCallBubble({
    super.key,
    required this.toolCall,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, statusText) = _getStateConfig(theme);

    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left border accent
          Container(
            width: 4,
            constraints: const BoxConstraints(minHeight: 48),
            decoration: BoxDecoration(
              color: color,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
            ),
          ),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header: icon + tool name + status
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          toolCall.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),

                  // Error message
                  if (toolCall.state == ToolCallState.error &&
                      toolCall.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        toolCall.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),

                  // Input arguments (expandable)
                  if (toolCall.input.isNotEmpty)
                    _ToolCallInputSection(input: toolCall.input),

                  // Output content
                  if (toolCall.state == ToolCallState.completed &&
                      toolCall.content.isNotEmpty)
                    _ToolCallOutputSection(content: toolCall.content),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color, Widget, String) _getStateConfig(ThemeData theme) {
    switch (toolCall.state) {
      case ToolCallState.pending:
        return (
          Colors.orange,
          const _PulsingIcon(icon: Icons.pending, color: Colors.orange),
          'Preparing...',
        );
      case ToolCallState.running:
        return (
          theme.colorScheme.primary,
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
          'Running...',
        );
      case ToolCallState.completed:
        return (
          Colors.green,
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          'Done',
        );
      case ToolCallState.error:
        return (
          theme.colorScheme.error,
          Icon(Icons.error, color: theme.colorScheme.error, size: 20),
          'Failed',
        );
    }
  }
}

/// Animated pulsing icon for pending state
class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;

  const _PulsingIcon({required this.icon, required this.color});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Icon(widget.icon, color: widget.color, size: 20),
        );
      },
    );
  }
}

/// Expandable section for tool call input arguments
class _ToolCallInputSection extends StatefulWidget {
  final Map<String, dynamic> input;

  const _ToolCallInputSection({required this.input});

  @override
  State<_ToolCallInputSection> createState() => _ToolCallInputSectionState();
}

class _ToolCallInputSectionState extends State<_ToolCallInputSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prettyJson = const JsonEncoder.withIndent('  ').convert(widget.input);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _expanded ? 'Hide input' : 'Show input',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                prettyJson,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Section for rendering tool call output content
class _ToolCallOutputSection extends StatelessWidget {
  final List<ToolContent> content;

  const _ToolCallOutputSection({required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: content.map((item) {
          if (item is ToolTextContent) {
            return Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: MarkdownBody(
                data: item.text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  code: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.primary,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
            );
          } else if (item is ToolFileContent) {
            return Chip(
              avatar: Icon(
                Icons.insert_drive_file,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              label: Text(
                item.name ?? 'File',
                style: theme.textTheme.bodySmall,
              ),
              backgroundColor:
                  theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              side: BorderSide.none,
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            );
          }
          return const SizedBox.shrink();
        }).toList(),
      ),
    );
  }
}
