import 'package:flutter/material.dart';

const spaceAccent = Color(0xFFADC6FF);

class SpaceColors extends ThemeExtension<SpaceColors> {
  const SpaceColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.card,
    required this.primaryText,
    required this.secondaryText,
    required this.disabled,
    required this.accent,
    required this.secondaryAccent,
    required this.tertiary,
    required this.onAccent,
    required this.danger,
    required this.warning,
    required this.dangerStrong,
    required this.outline,
    required this.outlineSubtle,
    required this.gradientTop,
    required this.gradientBottom,
    required this.navBackground,
    required this.chipBackground,
  });

  final Color background;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color card;
  final Color primaryText;
  final Color secondaryText;
  final Color disabled;
  final Color accent;
  final Color secondaryAccent;
  final Color tertiary;
  final Color onAccent;
  final Color danger;
  final Color warning;
  final Color dangerStrong;
  final Color outline;
  final Color outlineSubtle;
  final Color gradientTop;
  final Color gradientBottom;
  final Color navBackground;
  final Color chipBackground;

  static const dark = SpaceColors(
    background: Color(0xFF05070A),
    surface: Color(0xFF111417),
    card: Color(0x9911141B),
    primaryText: Color(0xFFE1E2E7),
    secondaryText: Color(0xFFC2C6D6),
    disabled: Color(0xFF8C909F),
    accent: Color(0xFFADC6FF),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFFFB4AB),
    warning: Color(0xFFFFD166),
    dangerStrong: Color(0xFFFF7B72),
    outline: Color(0x14FFFFFF),
    outlineSubtle: Color(0x0DFFFFFF),
    gradientTop: Color(0xFF111827),
    gradientBottom: Color(0xFF05070A),
    navBackground: Color(0x991D2023),
    chipBackground: Color(0x14282A2E),
  );

  static const light = SpaceColors(
    background: Color(0xFFF7F9FB),
    surface: Color(0xFFF7F9FB),
    card: Color(0xB3FFFFFF),
    primaryText: Color(0xFF0F172A),
    secondaryText: Color(0xFF475569),
    disabled: Color(0xFF767586),
    accent: Color(0xFF4648D4),
    onAccent: Color(0xFFFFFFFF),
    danger: Color(0xFFBA1A1A),
    warning: Color(0xFFD97706),
    dangerStrong: Color(0xFF93000A),
    outline: Color(0x99FFFFFF),
    outlineSubtle: Color(0x80E0E3E5),
    gradientTop: Color(0xFFE1E0FF),
    gradientBottom: Color(0xFFF7F9FB),
    navBackground: Color(0xCCFFFFFF),
    chipBackground: Color(0x66FFFFFF),
  );

  static SpaceColors of(BuildContext context) =>
      Theme.of(context).extension<SpaceColors>() ?? dark;

  @override
  SpaceColors copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? card,
    Color? primaryText,
    Color? secondaryText,
    Color? disabled,
    Color? accent,
    Color? secondaryAccent,
    Color? tertiary,
    Color? onAccent,
    Color? danger,
    Color? warning,
    Color? dangerStrong,
    Color? outline,
    Color? outlineSubtle,
    Color? gradientTop,
    Color? gradientBottom,
    Color? navBackground,
    Color? chipBackground,
  }) {
    return SpaceColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      card: card ?? this.card,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      disabled: disabled ?? this.disabled,
      accent: accent ?? this.accent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      tertiary: tertiary ?? this.tertiary,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      dangerStrong: dangerStrong ?? this.dangerStrong,
      outline: outline ?? this.outline,
      outlineSubtle: outlineSubtle ?? this.outlineSubtle,
      gradientTop: gradientTop ?? this.gradientTop,
      gradientBottom: gradientBottom ?? this.gradientBottom,
      navBackground: navBackground ?? this.navBackground,
      chipBackground: chipBackground ?? this.chipBackground,
    );
  }

  @override
  SpaceColors lerp(SpaceColors? other, double t) {
    if (other is! SpaceColors) return this;
    return SpaceColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      card: Color.lerp(card, other.card, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      secondaryAccent: Color.lerp(secondaryAccent, other.secondaryAccent, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      dangerStrong: Color.lerp(dangerStrong, other.dangerStrong, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      outlineSubtle: Color.lerp(outlineSubtle, other.outlineSubtle, t)!,
      gradientTop: Color.lerp(gradientTop, other.gradientTop, t)!,
      gradientBottom: Color.lerp(gradientBottom, other.gradientBottom, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
      chipBackground: Color.lerp(chipBackground, other.chipBackground, t)!,
    );
  }
}

class SpaceTypography {
  static const fontHeading = 'Montserrat';
  static const fontBody = 'Hanken Grotesk';
  static const fontMono = 'JetBrains Mono';

  static TextStyle headingLarge({
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double fontSize = 26,
    double? letterSpacing = -0.4,
  }) =>
      TextStyle(
        fontFamily: fontHeading,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFF8FAFC),
      );

  static TextStyle headingMedium({
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double fontSize = 18,
    double? letterSpacing = -0.2,
  }) =>
      TextStyle(
        fontFamily: fontHeading,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFF8FAFC),
      );

  static TextStyle headingSmall({
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double fontSize = 15,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontHeading,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFF8FAFC),
      );

  static TextStyle bodyLarge({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 15,
    double height = 1.4,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontBody,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFF8FAFC),
      );

  static TextStyle bodyMedium({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 13,
    double height = 1.4,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontBody,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFA1AAB8),
      );

  static TextStyle bodySmall({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 12,
    double height = 1.3,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: fontBody,
        fontSize: fontSize,
        fontWeight: fontWeight,
        height: height,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFF6B7280),
      );

  static TextStyle technical({
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 0.4,
  }) =>
      TextStyle(
        fontFamily: fontMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        color: color ?? const Color(0xFFA1AAB8),
      );
}

ThemeData buildSpaceTheme(Brightness brightness) {
  final colors = brightness == Brightness.dark
      ? SpaceColors.dark
      : SpaceColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.accent,
        brightness: brightness,
        primary: colors.accent,
        onPrimary: colors.onAccent,
      ).copyWith(
        surface: colors.surface,
        onSurface: colors.primaryText,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.danger,
        outline: colors.outline,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Hanken Grotesk',
    scaffoldBackgroundColor: colors.background,
    colorScheme: scheme,
    extensions: [colors],
    textSelectionTheme: TextSelectionThemeData(cursorColor: colors.accent),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outline, width: 1),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface2,
      contentTextStyle: SpaceTypography.bodyMedium(color: colors.primaryText),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline, width: 1),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.navBackground,
      elevation: 0,
      indicatorColor: colors.accent.withValues(alpha: 0.15),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            fontFamily: SpaceTypography.fontHeading,
            color: colors.accent,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          );
        }
        return TextStyle(
          fontFamily: SpaceTypography.fontHeading,
          color: colors.disabled,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
  );
}
