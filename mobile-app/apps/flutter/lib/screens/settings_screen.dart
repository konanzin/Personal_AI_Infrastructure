import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_lock_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import 'providers_screen.dart';
import '../l10n/app_localizations.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: Text(l10n.machines),
              subtitle: Text(l10n.machinesSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, '/machines'),
            ),
            ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(l10n.aiProviders),
              subtitle: Text(l10n.aiProvidersSubtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProvidersScreen()),
              ),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Text(l10n.appearance, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text(l10n.systemTheme),
                  icon: const Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text(l10n.lightTheme),
                  icon: const Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text(l10n.darkTheme),
                  icon: const Icon(Icons.dark_mode),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (s) => settings.setThemeMode(s.first),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: Text(l10n.dynamicColor),
              subtitle: Text(l10n.dynamicColorSubtitle),
              value: settings.useDynamicColor,
              onChanged: settings.setUseDynamicColor,
              contentPadding: EdgeInsets.zero,
            ),
            if (!settings.useDynamicColor) ...[
              const SizedBox(height: 8),
              Text(l10n.accentColor),
              const SizedBox(height: 8),
              _SeedColorPicker(settings: settings),
              const SizedBox(height: 16),
              Text(l10n.colorStyle),
              const SizedBox(height: 8),
              SegmentedButton<DynamicSchemeVariant>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: DynamicSchemeVariant.tonalSpot,
                    label: Text(l10n.colorStyleSoft),
                  ),
                  ButtonSegment(
                    value: DynamicSchemeVariant.vibrant,
                    label: Text(l10n.colorStyleVibrant),
                  ),
                  ButtonSegment(
                    value: DynamicSchemeVariant.fidelity,
                    label: Text(l10n.colorStyleFaithful),
                  ),
                  ButtonSegment(
                    value: DynamicSchemeVariant.expressive,
                    label: Text(l10n.colorStyleExpressive),
                  ),
                ],
                selected: {settings.schemeVariant},
                onSelectionChanged: (s) => settings.setSchemeVariant(s.first),
              ),
              const SizedBox(height: 8),
            ],
            SwitchListTile(
              title: Text(l10n.pureBlack),
              subtitle: Text(l10n.pureBlackSubtitle),
              value: settings.pureBlack,
              onChanged: settings.setPureBlack,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: Text(l10n.showThinking),
              subtitle: Text(l10n.showThinkingSubtitle),
              value: settings.showThinking,
              onChanged: settings.setShowThinking,
              contentPadding: EdgeInsets.zero,
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Text(l10n.pulseSectionTitle,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(l10n.pulseEnableTitle),
              subtitle: Text(l10n.pulseEnableSubtitle),
              value: settings.pulseEnabled,
              onChanged: settings.setPulseEnabled,
              contentPadding: EdgeInsets.zero,
            ),
            if (settings.pulseEnabled) ...[
              SwitchListTile(
                title: Text(l10n.pulseMilestones),
                value: settings.pulseSpeakMilestone,
                onChanged: (v) => settings.setPulseLevel(milestone: v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: Text(l10n.pulseAttention),
                value: settings.pulseSpeakAttention,
                onChanged: (v) => settings.setPulseLevel(attention: v),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                title: Text(l10n.pulseDigests),
                value: settings.pulseSpeakDigest,
                onChanged: (v) => settings.setPulseLevel(digest: v),
                contentPadding: EdgeInsets.zero,
              ),
            ],

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            Text(l10n.security, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Consumer<AppLockProvider>(
              builder: (ctx, lock, _) => Column(
                children: [
                  SwitchListTile(
                    title: Text(l10n.appLock),
                    subtitle: Text(lock.deviceAuthAvailable
                        ? l10n.appLockSubtitleAvailable
                        : l10n.appLockSubtitleUnavailable),
                    value: lock.lockEnabled,
                    contentPadding: EdgeInsets.zero,
                    onChanged: lock.deviceAuthAvailable
                        ? (v) => lock.setLockEnabled(v)
                        : null,
                  ),
                  if (lock.lockEnabled)
                    ListTile(
                      title: Text(l10n.lockTimeout),
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
      ),
    );
  }
}

/// Swatch grid for the theme seed. The live theme itself is the preview:
/// tapping a swatch reseeds the whole app immediately.
class _SeedColorPicker extends StatelessWidget {
  const _SeedColorPicker({required this.settings});

  final SettingsProvider settings;

  static const List<Color> _swatches = [
    AppTheme.defaultSeed, // PAI blue
    Color(0xFF6750A4), // M3 violet
    Color(0xFF7C4DFF), // deep purple
    Color(0xFF0B57D0), // google blue
    Color(0xFF06B6D4), // cyan
    Color(0xFF00897B), // teal
    Color(0xFF10B981), // green
    Color(0xFF84CC16), // lime
    Color(0xFFF59E0B), // amber
    Color(0xFFF97316), // orange
    Color(0xFFEF4444), // red
    Color(0xFFEC4899), // pink
  ];

  @override
  Widget build(BuildContext context) {
    final selected = settings.seedColor ?? AppTheme.defaultSeed;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final color in _swatches)
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => settings.setSeedColor(
                color == AppTheme.defaultSeed ? null : color),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected.toARGB32() == color.toARGB32()
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 3,
                      )
                    : null,
              ),
              child: selected.toARGB32() == color.toARGB32()
                  ? const Icon(Icons.check, color: Colors.white, size: 20)
                  : null,
            ),
          ),
      ],
    );
  }
}
