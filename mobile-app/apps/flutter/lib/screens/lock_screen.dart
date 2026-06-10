import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  bool _authInProgress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  Future<void> _authenticate() async {
    if (_authInProgress) return;
    setState(() {
      _authInProgress = true;
      _error = null;
    });

    final ok = await context.read<AppLockProvider>().authenticate();
    if (!mounted) return;

    setState(() {
      _authInProgress = false;
      _error = ok ? null : 'Authentication was cancelled or failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lockProvider = context.watch<AppLockProvider>();
    final label = lockProvider.biometricAvailable
        ? 'Unlock with biometrics or device PIN'
        : 'Unlock with device PIN';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text('PAI is locked', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _authInProgress || !lockProvider.deviceAuthAvailable
                    ? null
                    : _authenticate,
                icon: _authInProgress
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(_authInProgress ? 'Authenticating...' : 'Unlock'),
              ),
              if (!lockProvider.deviceAuthAvailable) ...[
                const SizedBox(height: 16),
                Text(
                  'Set up a screen lock in Android settings to use app lock.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
