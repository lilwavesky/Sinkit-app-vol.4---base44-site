import 'package:material_ui/material_ui.dart';
import 'package:google_fonts/google_fonts.dart';

class KarenColors {
  static const Color brandPurple = Color(0xFF5B21B6);
  static const Color brandDeepPurple = Color(0xFF1E1038);
  static const Color brandOrange = Color(0xFFF25C2A);
  static const Color brandBlue = Color(0xFF2563EB);
  static const Color successGreen = Color(0xFF16A34A);
  static const Color warningAmber = Color(0xFFD97706);
  static const Color dangerRed = Color(0xFFDC2626);
  static const Color surfaceLight = Color(0xFFF7F6FB);
  static const Color surfaceDark = Color(0xFF110D1B);
  static const Color cardDark = Color(0xFF1B152B);
}

class AppTheme {
  static const List<String> _persianFallbacks = ['NotoSansArabic'];

  static TextStyle _textStyle({
    required bool useGoogleFonts,
    required double fontSize,
    required FontWeight fontWeight,
    Color? color,
    double? height,
  }) {
    if (useGoogleFonts) {
      return GoogleFonts.vazirmatn(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      ).copyWith(fontFamilyFallback: _persianFallbacks);
    }
    return TextStyle(
      fontFamily: 'NotoSansArabic',
      fontFamilyFallback: _persianFallbacks,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );
  }

  static TextTheme _buildPersianTextTheme({
    required Brightness brightness,
    required bool useGoogleFonts,
  }) {
    final base = brightness == Brightness.light
        ? ThemeData.light().textTheme
        : ThemeData.dark().textTheme;
    final themed = useGoogleFonts
        ? GoogleFonts.vazirmatnTextTheme(base)
        : base.apply(fontFamily: 'NotoSansArabic');

    final primaryTextColor =
        brightness == Brightness.light ? KarenColors.brandDeepPurple : Colors.white;
    final secondaryTextColor = brightness == Brightness.light
        ? const Color(0xFF4B5563)
        : Colors.grey.shade300;

    return themed.copyWith(
      displaySmall: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: primaryTextColor,
      ),
      headlineSmall: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: primaryTextColor,
      ),
      titleLarge: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: primaryTextColor,
      ),
      titleMedium: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 15.5,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      titleSmall: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      bodyLarge: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: primaryTextColor,
        height: 1.55,
      ),
      bodyMedium: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 13.5,
        fontWeight: FontWeight.w400,
        color: primaryTextColor,
        height: 1.55,
      ),
      bodySmall: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondaryTextColor,
        height: 1.5,
      ),
      labelLarge: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      labelMedium: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: primaryTextColor,
      ),
      labelSmall: _textStyle(
        useGoogleFonts: useGoogleFonts,
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: secondaryTextColor,
      ),
    );
  }

  static ThemeData light({bool useGoogleFonts = true}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: KarenColors.brandPurple,
      primary: KarenColors.brandPurple,
      secondary: KarenColors.brandOrange,
      surface: KarenColors.surfaceLight,
      brightness: Brightness.light,
    );
    final textTheme = _buildPersianTextTheme(
      brightness: Brightness.light,
      useGoogleFonts: useGoogleFonts,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: useGoogleFonts ? GoogleFonts.vazirmatn().fontFamily : 'NotoSansArabic',
      fontFamilyFallback: _persianFallbacks,
      textTheme: textTheme,
      scaffoldBackgroundColor: KarenColors.surfaceLight,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: KarenColors.brandDeepPurple,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: KarenColors.brandDeepPurple,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: KarenColors.brandDeepPurple,
        ),
        contentTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          color: KarenColors.brandDeepPurple,
          height: 1.6,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade700,
        ),
        hintStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade500,
        ),
        helperStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade600,
        ),
        errorStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: KarenColors.dangerRed,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: KarenColors.brandPurple, width: 1.8),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: KarenColors.brandDeepPurple,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: KarenColors.brandDeepPurple,
        ),
        subtitleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: KarenColors.brandPurple.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? KarenColors.brandPurple : Colors.grey.shade700,
          );
        }),
      ),
    );
  }

  static ThemeData dark({bool useGoogleFonts = true}) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: KarenColors.brandPurple,
      primary: const Color(0xFFA78BFA),
      secondary: KarenColors.brandOrange,
      surface: KarenColors.surfaceDark,
      brightness: Brightness.dark,
    );
    final textTheme = _buildPersianTextTheme(
      brightness: Brightness.dark,
      useGoogleFonts: useGoogleFonts,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      fontFamily: useGoogleFonts ? GoogleFonts.vazirmatn().fontFamily : 'NotoSansArabic',
      fontFamilyFallback: _persianFallbacks,
      textTheme: textTheme,
      scaffoldBackgroundColor: KarenColors.surfaceDark,
      appBarTheme: AppBarTheme(
        backgroundColor: KarenColors.cardDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: KarenColors.cardDark,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: KarenColors.cardDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        contentTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13.5,
          fontWeight: FontWeight.w400,
          color: Colors.white,
          height: 1.6,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF251D3A),
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade300,
        ),
        hintStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade500,
        ),
        helperStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 11.5,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade400,
        ),
        errorStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          color: const Color(0xFFF87171),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFA78BFA), width: 1.8),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        labelStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        contentTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        subtitleTextStyle: _textStyle(
          useGoogleFonts: useGoogleFonts,
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Colors.grey.shade400,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: KarenColors.cardDark,
        indicatorColor: const Color(0xFFA78BFA).withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return _textStyle(
            useGoogleFonts: useGoogleFonts,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? const Color(0xFFA78BFA) : Colors.grey.shade400,
          );
        }),
      ),
    );
  }
}
