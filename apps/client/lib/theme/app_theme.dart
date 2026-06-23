import 'package:flutter/material.dart';

/// Centralized design system for the LabelOps admin app.
///
/// Goal: professional management-software feel, with a light/young accent.
/// - Refined teal-based ColorScheme with neutral text colors.
/// - Polished typography (weights / sizes / letter-spacing) on system fonts.
/// - Standardized spacing and corner-radius tokens.
/// - Themed NavigationRail, Card, Input, Button, SnackBar.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _buildLight();

  static ThemeData _buildLight() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.secondary,
      tertiary: AppColors.tertiary,
      surface: AppColors.surface,
      onSurface: AppColors.textStrong,
      onSurfaceVariant: AppColors.textMuted,
      surfaceContainerHighest: AppColors.surfaceAlt,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineSoft,
    );

    final textTheme = _buildTextTheme(colorScheme);

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.divider,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textStrong,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shadowColor: AppColors.shadow,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        space: 1,
        thickness: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textFaint),
        labelStyle: textTheme.labelLarge?.copyWith(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: colorScheme.error, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: AppColors.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          hoverColor: AppColors.hoverTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.chipSurface,
        labelStyle: textTheme.labelMedium,
        side: const BorderSide(color: AppColors.outlineSoft),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.sidebarSurface,
        elevation: 0,
        useIndicator: true,
        indicatorColor: AppColors.sidebarSelected,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        selectedIconTheme: const IconThemeData(
          color: AppColors.primary,
          size: 22,
        ),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.textMuted,
          size: 22,
        ),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: textTheme.labelLarge?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w500,
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
          insets: const EdgeInsets.symmetric(horizontal: 4),
        ),
        dividerColor: AppColors.divider,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textStrong,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.textStrong,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 400),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
        dataTextStyle: textTheme.bodyMedium,
        headingRowColor:
            WidgetStateProperty.all(AppColors.tableHeaderSurface),
        dividerThickness: 1,
        columnSpacing: 24,
        horizontalMargin: 16,
        dataRowMinHeight: 48,
        dataRowMaxHeight: 60,
        headingRowHeight: 44,
      ),
    );
  }

  static TextTheme _buildTextTheme(ColorScheme cs) {
    const ink = AppColors.textStrong;
    const muted = AppColors.textMuted;

    return TextTheme(
      displaySmall: const TextStyle(
        fontSize: 32,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.4,
      ),
      headlineLarge: const TextStyle(
        fontSize: 28,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.3,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: ink,
        letterSpacing: -0.2,
      ),
      headlineSmall: const TextStyle(
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: -0.1,
      ),
      titleLarge: const TextStyle(
        fontSize: 18,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      titleMedium: const TextStyle(
        fontSize: 15,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: 0.1,
      ),
      titleSmall: const TextStyle(
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: 0.1,
      ),
      bodyLarge: const TextStyle(
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        color: ink,
      ),
      bodySmall: const TextStyle(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: FontWeight.w400,
        color: muted,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: 0.1,
      ),
      labelMedium: const TextStyle(
        fontSize: 12,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.3,
      ),
      labelSmall: const TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: muted,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Brand and semantic color palette.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF156B5C);
  static const Color primarySoft = Color(0xFFE7F3F0);
  static const Color secondary = Color(0xFFDA8A6C);
  static const Color tertiary = Color(0xFFE47BAA);

  // Surfaces
  static const Color background = Color(0xFFF6F9F8);
  static const Color surface = Color(0xFFFCFEFD);
  static const Color surfaceAlt = Color(0xFFE7F3F0);
  static const Color cardSurface = Colors.white;
  static const Color sidebarSurface = Color(0xFFF1F6F5);
  static const Color sidebarSelected = Color(0xFFDDEDE9);
  static const Color tableHeaderSurface = Color(0xFFF4F8F7);
  static const Color chipSurface = Color(0xFFF1F6F5);
  static const Color hoverTint = Color(0x14156B5C);

  // Text
  static const Color textStrong = Color(0xFF0F2E2A);
  static const Color textMuted = Color(0xFF5C7472);
  static const Color textFaint = Color(0xFF9AAFAC);

  // Lines / borders
  static const Color outline = Color(0xFFD7E3E0);
  static const Color outlineSoft = Color(0xFFE6EEEC);
  static const Color divider = Color(0xFFE3ECEA);
  static const Color cardBorder = Color(0xFFE6EEEC);
  static const Color shadow = Color(0x14156B5C);

  // Status (light, professional accents)
  static const Color successSurface = Color(0xFFE8F5EE);
  static const Color successText = Color(0xFF146C3A);
  static const Color warningSurface = Color(0xFFFFF4E5);
  static const Color warningText = Color(0xFF8A5300);
  static const Color dangerSurface = Color(0xFFFDECEC);
  static const Color dangerText = Color(0xFFB42318);
  static const Color infoSurface = Color(0xFFE7F0FA);
  static const Color infoText = Color(0xFF1F5B9C);
}

/// Standardized corner-radius tokens.
class AppRadii {
  AppRadii._();

  static const double control = 12; // inputs, buttons, icon buttons
  static const double card = 18;    // cards / panels (soft but pro)
  static const double dialog = 20;  // dialogs / sheets
  static const double pill = 999;   // chips / badges
}

/// Standardized spacing scale (4-pt grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}
