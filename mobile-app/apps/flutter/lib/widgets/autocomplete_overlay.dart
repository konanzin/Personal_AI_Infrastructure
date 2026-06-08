import 'package:flutter/material.dart';

class AutocompleteSuggestion {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String insertText;

  const AutocompleteSuggestion({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.insertText,
  });
}

class AutocompleteOverlay extends StatelessWidget {
  final List<AutocompleteSuggestion> suggestions;
  final int highlightIndex;
  final ValueChanged<AutocompleteSuggestion> onSelect;

  const AutocompleteOverlay({
    super.key,
    required this.suggestions,
    this.highlightIndex = -1,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final maxVisible = suggestions.length.clamp(1, 6);
    const itemHeight = 48.0;
    final height = maxVisible * itemHeight;

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: height, maxWidth: 360),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: suggestions.length,
          itemBuilder: (ctx, i) {
            final s = suggestions[i];
            final isHighlighted = i == highlightIndex;
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onSelect(s),
              child: Container(
                height: itemHeight,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                color: isHighlighted
                    ? theme.colorScheme.primaryContainer.withAlpha(120)
                    : null,
                child: Row(
                  children: [
                    Icon(s.icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.title,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: isHighlighted ? FontWeight.w600 : null,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (s.subtitle != null)
                            Text(
                              s.subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
