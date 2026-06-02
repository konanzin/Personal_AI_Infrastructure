import 'package:flutter/material.dart';

/// Widget that shows an expandable reasoning section below an assistant message.
class ReasoningMessageBubble extends StatelessWidget {
  final String? reasoning;
  final bool isExpanded;
  final VoidCallback onToggle;

  const ReasoningMessageBubble({
    super.key,
    this.reasoning,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasReasoning = reasoning != null && reasoning!.isNotEmpty;

    if (!hasReasoning) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        TextButton.icon(
          onPressed: onToggle,
          icon: Icon(
            isExpanded ? Icons.expand_less : Icons.psychology,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          label: Text(
            isExpanded ? 'Hide reasoning' : 'Show reasoning',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.primary,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),

        // Expanded reasoning content
        if (isExpanded)
          Container(
            margin: const EdgeInsets.only(top: 4, left: 8, right: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.psychology,
                      size: 14,
                        color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Agent Reasoning',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reasoning!,
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
