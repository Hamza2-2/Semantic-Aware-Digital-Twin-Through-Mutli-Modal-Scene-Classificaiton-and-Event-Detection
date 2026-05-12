import 'package:flutter/material.dart';

class SorhusColors {
  static const Color hotPink = Color(0xFFFF4D9A);
  static const Color fuchsia = Color(0xFFEE4BFF);
  static const Color purple = Color(0xFF7F5AF0);
  static const Color blue = Color(0xFF3B82F6);
  static const Color brightBlue = Color(0xFF60A5FA);
  static const Color teal = Color(0xFF2DD4BF);
  static const Color green = Color(0xFF22C55E);
  static const Color softBackgroundLight = Color(0xFFF3F5FF);
  static const Color softBackgroundDark = Color(0xFF050816);
}

class AppTheme {
  static ThemeData get lightTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: SorhusColors.purple,
      brightness: Brightness.light,
      background: SorhusColors.softBackgroundLight,
    );

    final scheme = baseScheme.copyWith(
      surface: Colors.white,
      surfaceContainerHighest: Colors.white.withValues(alpha: 0.92),
      onSurface: const Color(0xFF111827),
      primary: SorhusColors.purple,
      secondary: SorhusColors.blue,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: SorhusColors.softBackgroundLight,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: SorhusColors.purple,
      brightness: Brightness.dark,
      background: SorhusColors.softBackgroundDark,
    );

    final scheme = baseScheme.copyWith(
      surface: const Color(0xFF0B1020),
      surfaceContainerHighest: const Color(0xFF15182B),
      onSurface: Colors.white.withValues(alpha: 0.92),
      primary: SorhusColors.purple,
      secondary: SorhusColors.brightBlue,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: SorhusColors.softBackgroundDark,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontFamily: 'SF Pro Text',
          fontSize: 14,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
    );
  }
}
