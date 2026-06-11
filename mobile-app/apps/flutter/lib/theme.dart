import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

/// Semantic color roles the M3 ColorScheme doesn't provide (success, warning,
/// diff colors). Derived from the active scheme and harmonized with its
/// primary so user-selected seeds and wallpaper colors never clash with them.
@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color diffAdded;
  final Color diffRemoved;

  const SemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.diffAdded,
    required this.diffRemoved,
  });

  factory SemanticColors.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    final source = scheme.primary;
    final green = (dark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
        .harmonizeWith(source);
    final orange = (dark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        .harmonizeWith(source);
    final red = (dark ? const Color(0xFFF87171) : const Color(0xFFB91C1C))
        .harmonizeWith(source);
    return SemanticColors(
      success: green,
      onSuccess: dark ? Colors.black : Colors.white,
      successContainer: green.withValues(alpha: dark ? 0.22 : 0.14),
      warning: orange,
      onWarning: dark ? Colors.black : Colors.white,
      warningContainer: orange.withValues(alpha: dark ? 0.22 : 0.14),
      diffAdded: green,
      diffRemoved: red,
    );
  }

  @override
  SemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? diffAdded,
    Color? diffRemoved,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      diffAdded: diffAdded ?? this.diffAdded,
      diffRemoved: diffRemoved ?? this.diffRemoved,
    );
  }

  @override
  SemanticColors lerp(SemanticColors? other, double t) {
    if (other == null) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      diffAdded: Color.lerp(diffAdded, other.diffAdded, t)!,
      diffRemoved: Color.lerp(diffRemoved, other.diffRemoved, t)!,
    );
  }
}

extension SemanticColorsX on ThemeData {
  SemanticColors get semanticColors =>
      extension<SemanticColors>() ??
      SemanticColors.fromScheme(colorScheme);
}

/// Seed-driven M3 theming.
///
/// Theme source cascade (decided 2026-06-10, see
/// docs/QUALITY_IMPROVEMENTS_ROADMAP.md): dynamic color (wallpaper, when
/// enabled) > user-selected seed > [defaultSeed]. The previous hand-built
/// OLED-black palette survives only as the optional [pureBlack] overrides.
class AppTheme {
  /// The blue that has been the app's identity color since the first theme.
  static const Color defaultSeed = Color(0xFF3B82F6);

  static ThemeData light({
    Color? seed,
    ColorScheme? dynamicScheme,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) {
    final scheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seed ?? defaultSeed,
          brightness: Brightness.light,
          dynamicSchemeVariant: variant,
        );
    return _build(scheme);
  }

  static ThemeData dark({
    Color? seed,
    ColorScheme? dynamicScheme,
    bool pureBlack = false,
    DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot,
  }) {
    var scheme = dynamicScheme ??
        ColorScheme.fromSeed(
          seedColor: seed ?? defaultSeed,
          brightness: Brightness.dark,
          dynamicSchemeVariant: variant,
        );
    if (pureBlack) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0D0D0D),
        surfaceContainer: const Color(0xFF141414),
        surfaceContainerHigh: const Color(0xFF1C1C1C),
        surfaceContainerHighest: const Color(0xFF242424),
      );
    }
    return _build(scheme, pureBlackSurface: pureBlack);
  }

  static ThemeData _build(ColorScheme scheme,
      {bool pureBlackSurface = false}) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: pureBlackSurface ? Colors.black : null,
      appBarTheme: pureBlackSurface
          ? const AppBarTheme(backgroundColor: Colors.black)
          : null,
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      extensions: [SemanticColors.fromScheme(scheme)],
    );
  }
}
