import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/settings_provider.dart';
import 'providers_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Machines'),
              subtitle: const Text('Set up SSH, bootstrap OpenCode, or use a direct server'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/machines'),
            ),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: const Text('AI Providers'),
              subtitle: const Text('Manage providers on the active machine'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProvidersScreen()),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Show thinking'),
              subtitle: const Text('Display agent reasoning steps'),
              value: settings.showThinking,
              onChanged: settings.setShowThinking,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Text('Security', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Consumer<AppLockProvider>(
              builder: (ctx, lock, _) => Column(
                children: [
                  SwitchListTile(
                    title: const Text('App Lock'),
                    subtitle: Text(lock.deviceAuthAvailable
                        ? 'Uses Android biometrics, PIN, password, or pattern'
                        : 'Set up a screen lock in Android settings first'),
                    value: lock.lockEnabled,
                    contentPadding: EdgeInsets.zero,
                    onChanged: lock.deviceAuthAvailable
                        ? (v) => lock.setLockEnabled(v)
                        : null,
                  ),
                  if (lock.lockEnabled)
                    ListTile(
                      title: const Text('Lock Timeout'),
                      subtitle: Text(lock.lockTimeout.label),
                      contentPadding: EdgeInsets.zero,
                      trailing: DropdownButton<LockTimeout>(
                        value: lock.lockTimeout,
                        underline: const SizedBox.shrink(),
                        onChanged: (v) {
                          if (v != null) lock.setLockTimeout(v);
                        },
                        items: LockTimeout.values
                            .map((t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(t.label),
                                ))
                            .toList(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
