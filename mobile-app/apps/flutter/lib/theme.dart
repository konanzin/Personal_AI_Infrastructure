import 'package:flutter/material.dart';

class AppTheme {
  static const _paiBlue = Color(0xFF3B82F6);
  static const _black = Color(0xFF000000);
  static const _nearBlack = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF1A1A1A);
  static const _surfaceContainer = Color(0xFF222222);
  static const _surfaceContainerHigh = Color(0xFF2A2A2A);
  static const _outline = Color(0xFF333333);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _black,
    colorScheme: const ColorScheme.dark(
      primary: _paiBlue,
      onPrimary: Colors.white,
      secondary: _paiBlue,
      surface: _nearBlack,
      onSurface: Colors.white,
      surfaceContainerHighest: _surfaceContainerHigh,
      surfaceContainerHigh: _surfaceContainer,
      surfaceContainer: _surface,
      outline: _outline,
      outlineVariant: Color(0xFF2C2C2C),
      error: Color(0xFFEF4444),
      onSurfaceVariant: Color(0xFF9CA3AF),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _black,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      iconTheme: IconThemeData(color: Colors.white),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: _nearBlack,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: _surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: const DividerThemeData(color: _outline, thickness: 0.5),
    iconTheme: const IconThemeData(color: Colors.white70),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white, fontSize: 16),
      bodyMedium: TextStyle(color: Colors.white, fontSize: 14),
      bodySmall: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
      titleLarge: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
    ),
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _paiBlue,
      brightness: Brightness.light,
    ),
  );
}
