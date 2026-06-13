import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/message_part.dart';
import '../theme.dart';

class ToolCallBubble extends StatefulWidget {
  final ToolCallPart toolCall;

  const ToolCallBubble({
    super.key,
    required this.toolCall,
  });

  @override
  State<ToolCallBubble> createState() => _ToolCallBubbleState();
}

class _ToolCallBubbleState extends State<ToolCallBubble> {
  bool _expanded = false;

  /// OpenCode spawns subagents through a tool named `task`, whose input
  /// carries `subagent_type` and a `description`. We render those as a
  /// distinct "subagent" row instead of a generic tool call.
  bool get _isSubagent => widget.toolCall.name == 'task';

  String get _subagentType => (widget.toolCall.input['subagent_type'] ??
          widget.toolCall.input['subagentType'] ??
          'agent')
      .toString();

  String? get _subagentDescription {
    final d = widget.toolCall.input['description']?.toString();
    return (d != null && d.trim().isNotEmpty) ? d.trim() : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (color, icon, statusText) = _getStateConfig(theme);
    final hasExpandableContent = _hasContent();

    final isSub = _isSubagent;
    final label = isSub
        ? (_subagentDescription ?? '$_subagentType subagent')
        : widget.toolCall.name;
    final leadingIcon = isSub
        ? Icon(Icons.account_tree_outlined,
            size: 16, color: theme.colorScheme.primary)
        : icon;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: hasExpandableContent
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isSub
                    ? theme.colorScheme.primaryContainer.withAlpha(60)
                    : theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  leadingIcon,
                  const SizedBox(width: 8),
                  if (isSub)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _subagentType,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    statusText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w500,
                      fontSize: 11,
                    ),
                  ),
                  if (hasExpandableContent) ...[
                    const SizedBox(width: 4),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) _buildExpandedContent(theme),
        ],
      ),
    );
  }

  bool _hasContent() {
    if (widget.toolCall.state == ToolCallState.error &&
        widget.toolCall.errorMessage != null) {
      return true;
    }
    if (widget.toolCall.input.keys.any((k) => !k.startsWith('_'))) {
      return true;
    }
    if (widget.toolCall.state == ToolCallState.completed &&
        widget.toolCall.content.isNotEmpty) {
      return true;
    }
    return false;
  }

  Widget _buildExpandedContent(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(top: 4, left: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(50),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
              color: theme.colorScheme.outline.withAlpha(80), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: 'Copy',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _copyableText()));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Copied'),
                        duration: Duration(seconds: 1)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.content_copy,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          if (widget.toolCall.state == ToolCallState.error &&
              widget.toolCall.errorMessage != null)
            Text(
              widget.toolCall.errorMessage!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          if (widget.toolCall.input.keys.any((k) => !k.startsWith('_')))
            _buildInput(theme),
          if (widget.toolCall.state == ToolCallState.completed &&
              widget.toolCall.content.isNotEmpty)
            _buildOutput(theme),
        ],
      ),
    );
  }

  /// Plain-text rendering of the tool call (input + output) for the clipboard.
  String _copyableText() {
    final buffer = StringBuffer();
    final filtered = Map.fromEntries(
      widget.toolCall.input.entries.where((e) => !e.key.startsWith('_')),
    );
    if (filtered.isNotEmpty) {
      buffer.writeln(const JsonEncoder.withIndent('  ').convert(filtered));
    }
    if (widget.toolCall.errorMessage != null) {
      buffer.writeln(widget.toolCall.errorMessage);
    }
    for (final item in widget.toolCall.content) {
      if (item is ToolTextContent) buffer.writeln(item.text);
    }
    return buffer.toString().trimRight();
  }

  Widget _buildInput(ThemeData theme) {
    final filtered = Map.fromEntries(
      widget.toolCall.input.entries.where((e) => !e.key.startsWith('_')),
    );
    final prettyJson = const JsonEncoder.withIndent('  ').convert(filtered);
    return SelectableText(
      prettyJson,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildOutput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: widget.toolCall.content.map((item) {
        if (item is ToolTextContent) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: MarkdownBody(
              data: item.text,
              styleSheet: MarkdownStyleSheet(
                p: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                code: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
          );
        } else if (item is ToolFileContent) {
          return Chip(
            avatar: Icon(Icons.insert_drive_file,
                size: 14, color: theme.colorScheme.primary),
            label: Text(item.name ?? 'File', style: theme.textTheme.bodySmall),
            backgroundColor: theme.colorScheme.primaryContainer.withAlpha(80),
            side: BorderSide.none,
            padding: EdgeInsets.zero,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          );
        }
        return const SizedBox.shrink();
      }).toList(),
    );
  }

  (Color, Widget, String) _getStateConfig(ThemeData theme) {
    switch (widget.toolCall.state) {
      case ToolCallState.pending:
        return (
          theme.semanticColors.warning,
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: theme.semanticColors.warning)),
          'Preparing...',
        );
      case ToolCallState.running:
        return (
          theme.colorScheme.primary,
          SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: theme.colorScheme.primary)),
          'Running...',
        );
      case ToolCallState.completed:
        return (
          theme.semanticColors.success,
          Icon(Icons.check_circle,
              color: theme.semanticColors.success, size: 16),
          'Done',
        );
      case ToolCallState.error:
        return (
          theme.colorScheme.error,
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 16),
          'Failed',
        );
      case ToolCallState.interrupted:
        return (
          theme.colorScheme.onSurfaceVariant,
          Icon(Icons.do_not_disturb_on_outlined,
              color: theme.colorScheme.onSurfaceVariant, size: 16),
          'Interrupted',
        );
    }
  }
}
