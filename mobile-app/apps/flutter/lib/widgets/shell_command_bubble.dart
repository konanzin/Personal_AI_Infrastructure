import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/message_part.dart';
import '../theme.dart';

/// Widget that renders a shell command with its output.
///
/// Shows the command in a terminal-like container with:
/// - Command in green monospace with copy button
/// - Scrollable output in dark container
/// - Copy button for output
///
/// The grey shades here are deliberate: the bubble mimics a terminal and
/// stays dark in both light and dark themes (like fenced code blocks), so it
/// intentionally does not follow the ColorScheme surfaces.
class ShellCommandBubble extends StatelessWidget {
  final ShellPart shell;

  const ShellCommandBubble({
    super.key,
    required this.shell,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.grey.shade700,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Command header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal,
                  size: 16,
                  color: Theme.of(context).semanticColors.success,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '\$ ${shell.command}',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: Theme.of(context).semanticColors.success,
                      fontSize: 13,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  onPressed: () => _copyToClipboard(context, shell.command),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy command',
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(
            height: 1,
            color: Colors.grey.shade700,
          ),
          
          // Output
          if (shell.output.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: SelectableText(
                  shell.output,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.grey.shade300,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          
          // Copy output button
          if (shell.output.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copyToClipboard(context, shell.output),
                  icon: Icon(
                    Icons.copy,
                    size: 14,
                    color: Colors.grey.shade400,
                  ),
                  label: Text(
                    'Copy output',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}
