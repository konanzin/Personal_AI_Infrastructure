import 'package:flutter/material.dart';

import '../services/git_status_service.dart';

class GitStatusBadge extends StatelessWidget {
  final GitStatus status;

  const GitStatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = status.branch;
    if (branch == null) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.commit, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 2),
        Text(branch,
            style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
        if (status.isDirty) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${status.changedFileCount}',
                style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

/// Inline display for the chat header -- branch + dirty indicator.
class GitStatusInline extends StatelessWidget {
  final GitStatus status;

  const GitStatusInline({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = status.branch;
    if (branch == null) return const SizedBox.shrink();

    final label = status.isDirty
        ? '$branch +${status.changedFileCount}'
        : branch;

    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        fontSize: 10,
        color: status.isDirty
            ? theme.colorScheme.error
            : theme.colorScheme.onSurfaceVariant,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
