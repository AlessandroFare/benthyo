import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF0A2342);
  static const accent = Color(0xFF00E5FF);
  static const backgroundDark = Color(0xFF080E18); // deep ocean navy
  static const surfaceDark = Color(0xFF111823);
  static const surfaceLight = Color(0xFFF6F8FA);
  static const error = Color(0xFFFF6B6B);
  static const success = Color(0xFF3FB950);
  static const textSecondary = Color(0xFF8B949E);

  // Semantic extensions ------------------------------------------------------
  static const warning = Color(0xFFE3A008);
  static const info = Color(0xFF58A6FF);

  /// Ocean depth palette: shallow -> deep. Used for depth badges, headers
  /// and anywhere the UI should evoke the water column.
  static const oceanShallow = Color(0xFF14B8C4);
  static const oceanMid = Color(0xFF0E5F8A);
  static const oceanDeep = Color(0xFF0A2342);
  static const oceanAbyss = Color(0xFF06121F);

  /// Elevated dark surface (one step above [surfaceDark]).
  static const surfaceDarkHigh = Color(0xFF1D242D);
  static const borderDark = Color(0xFF30363D);

  /// Hero / header gradient evoking descent through the water column.
  static const oceanGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [oceanMid, oceanDeep, oceanAbyss],
  );

  /// Subtle horizontal gradient for accents (chips, progress, rings).
  static const accentGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [accent, oceanShallow],
  );

  /// Returns a colour representing a depth in metres (shallow teal to
  /// deep navy). Keeps depth badges instantly scannable in the logbook.
  static Color depthColor(double meters) {
    if (meters < 12) return oceanShallow;
    if (meters < 25) return oceanMid;
    if (meters < 40) return oceanDeep;
    return oceanAbyss;
  }
}

class AppSpacing {
  static const minTapTarget = 48.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Corner radius tokens - keep every rounded surface consistent.
class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const full = 999.0;
}

/// Motion tokens - all animations in the app should pick from these so the
/// interface feels coherent.
class AppDurations {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const stagger = Duration(milliseconds: 50);
}

/// Easing tokens.
class AppCurves {
  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeOutQuart;
  static const spring = Curves.easeOutBack;
}

class AppTheme {
  static TextTheme _textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? ThemeData.dark(useMaterial3: true).textTheme
        : ThemeData.light(useMaterial3: true).textTheme;

    final body = GoogleFonts.interTextTheme(base);
    final display = GoogleFonts.spaceGroteskTextTheme(base);

    return body.copyWith(
      displayLarge: display.displayLarge,
      displayMedium: display.displayMedium,
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
      headlineSmall: display.headlineSmall,
      titleLarge: display.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: display.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surfaceLight,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.surfaceLight,
      textTheme: _textTheme(Brightness.light),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.white,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        indicatorColor: AppColors.accent.withValues(alpha: 0.2),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 12),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
      ),
      splashColor: AppColors.primary.withValues(alpha: 0.08),
      highlightColor: AppColors.primary.withValues(alpha: 0.05),
      dividerTheme: DividerThemeData(
        color: Colors.grey.shade300,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        side: BorderSide(color: Colors.grey.shade300),
        labelStyle: GoogleFonts.inter(fontSize: 13),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.oceanDeep,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      primary: AppColors.accent,
      onPrimary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.surfaceDark,
      error: AppColors.error,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.backgroundDark,
      textTheme: _textTheme(Brightness.dark),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppColors.borderDark.withValues(alpha: 0.8)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          foregroundColor: AppColors.accent,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: AppColors.surfaceDark,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppColors.surfaceDark,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: Colors.white70, size: 22),
        ),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
        ),
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.primary,
      ),
      splashColor: AppColors.accent.withValues(alpha: 0.08),
      highlightColor: AppColors.accent.withValues(alpha: 0.05),
      dividerTheme: const DividerThemeData(
        color: AppColors.borderDark,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        side: const BorderSide(color: AppColors.borderDark),
        labelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.white70),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfaceDarkHigh,
        contentTextStyle: GoogleFonts.inter(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceDarkHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    );
  }

  /// Sunlight high-contrast theme.
  ///
  /// Tuned for topside use in bright Mediterranean glare and for divers
  /// reading the screen with the sun overhead. Design rules:
  ///   - Near-white background with very dark, high-contrast text
  ///     (maximises legibility under glare; AA/AAA on body text).
  ///   - Primary actions use the deep navy fill (NOT the bright cyan
  ///     accent, which washes out and loses contrast in sunlight).
  ///   - Thicker borders and larger min tap targets keep targets findable
  ///     with wet/gloved hands.
  static ThemeData sunlight() {
    const sunBg = Color(0xFFFFFFFF);
    const sunSurface = Color(0xFFEFF3F7);
    const sunText = Color(0xFF06121F); // near-black navy, very high contrast
    const sunBorder = Color(0xFF0A2342);

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primary,
      surface: sunSurface,
      onSurface: sunText,
      error: const Color(0xFFC1121F), // darker red for contrast
    );

    final base = _textTheme(Brightness.light).apply(
      bodyColor: sunText,
      displayColor: sunText,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: sunBg,
      textTheme: base,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: sunBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: sunBorder, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppSpacing.minTapTarget, 56),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(AppSpacing.minTapTarget, 56),
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: sunBorder, width: 2),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize:
              const Size(AppSpacing.minTapTarget, AppSpacing.minTapTarget),
          foregroundColor: sunText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: sunBorder, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: sunBorder, width: 1.5),
        ),
        filled: true,
        fillColor: sunBg,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: sunBg,
        indicatorColor: AppColors.primary.withValues(alpha: 0.18),
        labelTextStyle: WidgetStatePropertyAll(
          GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600,
              color: sunText),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(
        color: sunBorder,
        thickness: 1.5,
        space: 1.5,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.oceanAbyss,
        contentTextStyle:
            GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
    );
  }

  static ThemeData get lightTheme => light();
  static ThemeData get darkTheme => dark();
  static ThemeData get sunlightTheme => sunlight();
}
