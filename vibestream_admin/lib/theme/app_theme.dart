import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Color tokens from the "Vibrant Pulse" design system.
class AppColors {
  static const surface = Color(0xFFFAF8FF);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF2F3FF);
  static const surfaceContainer = Color(0xFFEAEDFF);
  static const surfaceContainerHigh = Color(0xFFE2E7FF);
  static const surfaceContainerHighest = Color(0xFFDAE2FD);
  static const onSurface = Color(0xFF131B2E);
  static const onSurfaceVariant = Color(0xFF464554);
  static const outline = Color(0xFF767586);
  static const outlineVariant = Color(0xFFC7C4D7);

  // Electric Indigo — primary
  static const primary = Color(0xFF4648D4);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF6063EE);

  // Bright Coral — secondary / alerts / destructive
  static const secondary = Color(0xFFB60E3D);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFFDA3054);

  // Mint — tertiary / success
  static const tertiary = Color(0xFF006859);
  static const tertiaryContainer = Color(0xFF008471);

  static const error = Color(0xFFBA1A1A);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.surface,
      colorScheme: const ColorScheme.light(
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        tertiary: AppColors.tertiary,
        error: AppColors.error,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surfaceContainerLowest: AppColors.surfaceContainerLowest,
        surfaceContainerLow: AppColors.surfaceContainerLow,
        surfaceContainer: AppColors.surfaceContainer,
        surfaceContainerHigh: AppColors.surfaceContainerHigh,
        surfaceContainerHighest: AppColors.surfaceContainerHighest,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.plusJakartaSans(
            fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.onSurface),
        headlineLarge: GoogleFonts.plusJakartaSans(
            fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.onSurface),
        headlineMedium: GoogleFonts.plusJakartaSans(
            fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.onSurface),
        bodyLarge: GoogleFonts.beVietnamPro(fontSize: 18, color: AppColors.onSurface),
        bodyMedium: GoogleFonts.beVietnamPro(fontSize: 16, color: AppColors.onSurface),
        labelMedium: GoogleFonts.beVietnamPro(
            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurfaceVariant),
        labelSmall: GoogleFonts.beVietnamPro(
            fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.onSurfaceVariant),
      ),
      fontFamily: GoogleFonts.beVietnamPro().fontFamily,
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.outlineVariant, width: 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.onSurface,
          side: const BorderSide(color: AppColors.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }
}
