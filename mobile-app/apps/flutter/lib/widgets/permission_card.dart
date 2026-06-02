import 'package:flutter/material.dart';

import '../models/chat_event.dart';

/// Card que exibe uma solicitação de permissão do agente PAI.
///
/// Apresenta o nome da permissão, os padrões afetados e três ações:
/// Allow Once, Always e Deny.
class PermissionCard extends StatelessWidget {
  final PermissionRequest request;
  final ValueChanged<PermissionReply> onReply;

  const PermissionCard({
    super.key,
    required this.request,
    required this.onReply,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warningColor = theme.colorScheme.errorContainer;
    final onWarning = theme.colorScheme.onErrorContainer;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.error.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: shield icon + "Permission Required"
            Row(
              children: [
                Icon(Icons.shield, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Text(
                  'Permission Required',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: onWarning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Body: "PAI wants to execute:" + permission name
            Text(
              'PAI wants to execute:',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: warningColor.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                request.permission,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: onWarning,
                ),
              ),
            ),

            // Patterns affected
            if (request.patterns.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Patterns affected:',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: request.patterns.map((pattern) {
                  return Chip(
                    label: Text(
                      pattern,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    backgroundColor: warningColor.withValues(alpha: 0.2),
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ],

            const SizedBox(height: 16),

            // Action buttons row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onReply(PermissionReply.once),
                    child: const Text('Allow Once'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onReply(PermissionReply.always),
                    child: const Text('Always'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextButton(
                    onPressed: () => onReply(PermissionReply.reject),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('Deny'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
