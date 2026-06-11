import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/file_change.dart';
import '../theme.dart';

/// Expandable card showing a file change with optional unified diff.
class FileDiffCard extends StatefulWidget {
  final FileChange change;

  const FileDiffCard({super.key, required this.change});

  @override
  State<FileDiffCard> createState() => _FileDiffCardState();
}

class _FileDiffCardState extends State<FileDiffCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = widget.change;
    final filename = change.path.split('/').last;
    final (icon, color) = _iconForType(change.type, theme);

    return Container(
      margin: const EdgeInsets.only(bottom: 6, left: 8, right: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: change.diff != null
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filename,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (change.path != filename)
                          Text(
                            change.path,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (change.diff != null)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && change.diff != null) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: _DiffText(diff: change.diff!),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 4),
                child: InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: change.diff!));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Diff copied'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.copy, size: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text('Copy diff',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _iconForType(FileChangeType type, ThemeData theme) {
    return switch (type) {
      FileChangeType.created =>
        (Icons.add_circle_outline, theme.semanticColors.diffAdded),
      FileChangeType.deleted =>
        (Icons.remove_circle_outline, theme.semanticColors.diffRemoved),
      FileChangeType.edited =>
        (Icons.edit_outlined, theme.semanticColors.warning),
      FileChangeType.diff =>
        (Icons.difference_outlined, theme.colorScheme.primary),
    };
  }
}

/// Renders unified diff text with line-level coloring.
class _DiffText extends StatelessWidget {
  final String diff;
  const _DiffText({required this.diff});

  @override
  Widget build(BuildContext context) {
    final lines = diff.split('\n');
    final theme = Theme.of(context);
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
        children: lines.map((line) {
          final Color color;
          if (line.startsWith('+') && !line.startsWith('+++')) {
            color = theme.semanticColors.diffAdded;
          } else if (line.startsWith('-') && !line.startsWith('---')) {
            color = theme.semanticColors.diffRemoved;
          } else if (line.startsWith('@@')) {
            color = theme.colorScheme.tertiary;
          } else {
            color = theme.colorScheme.onSurfaceVariant;
          }
          return TextSpan(text: '$line\n', style: TextStyle(color: color));
        }).toList(),
      ),
    );
  }
}
