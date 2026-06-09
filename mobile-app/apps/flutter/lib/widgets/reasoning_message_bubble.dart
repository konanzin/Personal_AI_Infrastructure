import 'package:flutter/material.dart';

/// Compact reasoning indicator inspired by OpenCode's TUI style.
/// Self-contained StatefulWidget that manages its own expand/collapse state.
class ReasoningMessageBubble extends StatefulWidget {
  final String reasoning;

  const ReasoningMessageBubble({
    super.key,
    required this.reasoning,
  });

  @override
  State<ReasoningMessageBubble> createState() => _ReasoningMessageBubbleState();
}

class _ReasoningMessageBubbleState extends State<ReasoningMessageBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const accentColor = Color(0xFFE5A52B);

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
                color: accentColor.withAlpha(15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _expanded ? Icons.remove : Icons.add,
                    size: 14,
                    color: accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thought',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: accentColor.withAlpha(180),
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
                  left: BorderSide(color: accentColor.withAlpha(80), width: 2),
                ),
              ),
              child: Text(
                widget.reasoning,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
