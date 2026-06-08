import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// Indicador de status de conexão minimalista
class ConnectionStatusIndicator extends StatelessWidget {
  final ConnectionStatus state;
  final VoidCallback? onReconnect;
  final bool compact;

  const ConnectionStatusIndicator({
    super.key,
    required this.state,
    this.onReconnect,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact();
    }
    return _buildFull(context);
  }

  Widget _buildCompact() {
    final (color, icon) = switch (state) {
      ConnectionStatus.online => (Colors.green, Icons.cloud_done),
      ConnectionStatus.connecting => (Colors.orange, Icons.cloud_sync),
      ConnectionStatus.offline => (Colors.red, Icons.cloud_off),
      ConnectionStatus.error => (Colors.red.shade700, Icons.error_outline),
    };

    final child = state == ConnectionStatus.connecting
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          )
        : Icon(icon, color: color, size: 22);

    if (state == ConnectionStatus.offline || state == ConnectionStatus.error) {
      return GestureDetector(
        onTap: onReconnect,
        child: child,
      );
    }

    return child;
  }

  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    
    switch (state) {
      case ConnectionStatus.online:
        return _buildStatus(
          theme,
          color: Colors.green,
          icon: Icons.cloud_done,
          label: 'Online',
        );
      case ConnectionStatus.connecting:
        return _buildStatus(
          theme,
          color: Colors.orange,
          icon: Icons.cloud_sync,
          label: 'Connecting...',
          showSpinner: true,
        );
      case ConnectionStatus.offline:
        return GestureDetector(
          onTap: onReconnect,
          child: _buildStatus(
            theme,
            color: Colors.red,
            icon: Icons.cloud_off,
            label: 'Offline - Tap to reconnect',
          ),
        );
      case ConnectionStatus.error:
        return GestureDetector(
          onTap: onReconnect,
          child: _buildStatus(
            theme,
            color: Colors.red.shade700,
            icon: Icons.error_outline,
            label: 'Error - Tap to retry',
          ),
        );
    }
  }

  Widget _buildStatus(
    ThemeData theme, {
    required Color color,
    required IconData icon,
    required String label,
    bool showSpinner = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            )
          else
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
