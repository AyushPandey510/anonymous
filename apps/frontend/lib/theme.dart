import 'package:flutter/material.dart';

const spaceAccent = Color(0xFFADC6FF);

/// Semantic color roles for the Space design system.
///
/// Uses a small, disciplined palette. Surfaces are solid and rely on
/// contrast and borders rather than translucency, glow, or shadows.
class SpaceColors extends ThemeExtension<SpaceColors> {
  const SpaceColors({
    required this.background,
    required this.surface,
    required this.surface2,
    required this.card,
    required this.primaryText,
    required this.secondaryText,
    required this.muted,
    required this.accent,
    required this.secondaryAccent,
    required this.primary,
    required this.onPrimary,
    required this.tertiary,
    required this.warning,
    required this.danger,
    required this.divider,
    required this.navBackground,
  });

  /// App-wide background.
  final Color background;

  /// Default solid surface (cards, dialogs, chat bubbles).
  final Color surface;

  /// Raised / control surface (inputs, chips, elevated controls).
  final Color surface2;

  /// Nested surface on top of [surface] (bubbles over chat background).
  final Color card;

  /// Primary text.
  final Color primaryText;

  /// Supporting text.
  final Color secondaryText;

  /// Muted text (timestamps, hints, captions).
  final Color muted;

  /// Brand accent (links, focus, highlights).
  final Color accent;

  /// Secondary brand accent (only used in the small brand gradient).
  final Color secondaryAccent;

  /// Solid fill for filled buttons / primary actions.
  final Color primary;

  /// Text/icon on [primary].
  final Color onPrimary;

  /// Success / geofence "inside".
  final Color tertiary;

  /// Warning / near-boundary.
  final Color warning;

  /// Error / destructive.
  final Color danger;

  /// Hairline dividers and borders.
  final Color divider;

  /// Bottom navigation bar.
  final Color navBackground;

  static const dark = SpaceColors(
    background: Color(0xFF05070A),
    surface: Color(0xFF111417),
    surface2: Color(0xFF1B212A),
    card: Color(0xFF151A21),
    primaryText: Color(0xFFE9EBF0),
    secondaryText: Color(0xFF9AA3B4),
    muted: Color(0xFF697283),
    accent: Color(0xFFADC6FF),
    secondaryAccent: Color(0xFFB79CFF),
    primary: Color(0xFFADC6FF),
    onPrimary: Color(0xFF0B0F1B),
    tertiary: Color(0xFF3BD69B),
    warning: Color(0xFFFFD166),
    danger: Color(0xFFFF8A80),
    divider: Color(0xFF1F2630),
    navBackground: Color(0xFF0F1319),
  );

  static const light = SpaceColors(
    background: Color(0xFFF4E7D0),
    surface: Color(0xFFFBF6EA),
    surface2: Color(0xFFEFE3CC),
    card: Color(0xFFFDF9F0),
    primaryText: Color(0xFF221D15),
    secondaryText: Color(0xFF5F5544),
    muted: Color(0xFF85795F),
    accent: Color(0xFFC45A11),
    secondaryAccent: Color(0xFF8F3208),
    primary: Color(0xFF8F3208),
    onPrimary: Color(0xFFFFFFFF),
    tertiary: Color(0xFF1F735C),
    warning: Color(0xFF9A4A05),
    danger: Color(0xFFB3261E),
    divider: Color(0xFFE6DAC1),
    navBackground: Color(0xFFFAF3E4),
  );

  static SpaceColors of(BuildContext context) =>
      Theme.of(context).extension<SpaceColors>() ?? dark;

  @override
  SpaceColors copyWith({
    Color? background,
    Color? surface,
    Color? surface2,
    Color? card,
    Color? primaryText,
    Color? secondaryText,
    Color? muted,
    Color? accent,
    Color? secondaryAccent,
    Color? primary,
    Color? onPrimary,
    Color? tertiary,
    Color? warning,
    Color? danger,
    Color? divider,
    Color? navBackground,
  }) {
    return SpaceColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      card: card ?? this.card,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      muted: muted ?? this.muted,
      accent: accent ?? this.accent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      tertiary: tertiary ?? this.tertiary,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      divider: divider ?? this.divider,
      navBackground: navBackground ?? this.navBackground,
    );
  }

  @override
  SpaceColors lerp(SpaceColors? other, double t) {
    if (other is! SpaceColors) return this;
    return SpaceColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      card: Color.lerp(card, other.card, t)!,
      primaryText: Color.lerp(primaryText, other.primaryText, t)!,
      secondaryText: Color.lerp(secondaryText, other.secondaryText, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      secondaryAccent: Color.lerp(secondaryAccent, other.secondaryAccent, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      navBackground: Color.lerp(navBackground, other.navBackground, t)!,
    );
  }
}

/// Restrained type scale. 11–26px, selective bold.
class SpaceTypography {
  // Referenced families are not bundled; Flutter resolves to the default
  // platform font. Kept as constants for forward compatibility.
  static const fontHeading = 'Montserrat';
  static const fontBody = 'Hanken Grotesk';
  static const fontMono = 'JetBrains Mono';

  static TextStyle display({
    Color? color,
  }) => TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w700,
    height: 1.18,
    letterSpacing: -0.4,
    color: color ?? const Color(0xFFF8FAFC),
  );

  static TextStyle headingLarge({
    Color? color,
    FontWeight fontWeight = FontWeight.w700,
    double fontSize = 20,
    double? letterSpacing = 0,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: 1.2,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFFF8FAFC),
  );

  static TextStyle headingMedium({
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double fontSize = 18,
    double? letterSpacing = 0,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: 1.25,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFFF8FAFC),
  );

  static TextStyle headingSmall({
    Color? color,
    FontWeight fontWeight = FontWeight.w600,
    double fontSize = 16,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: 1.25,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFFF8FAFC),
  );

  static TextStyle bodyLarge({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 15,
    double height = 1.4,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFFF8FAFC),
  );

  static TextStyle bodyMedium({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 14,
    double height = 1.4,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFFA1AAB8),
  );

  static TextStyle bodySmall({
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double fontSize = 13,
    double height = 1.35,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFF6B7280),
  );

  static TextStyle caption({
    Color? color,
    FontWeight fontWeight = FontWeight.w500,
    double fontSize = 12,
    double height = 1.3,
    double? letterSpacing = 0.1,
  }) => TextStyle(
    fontSize: fontSize,
    fontWeight: fontWeight,
    height: height,
    letterSpacing: letterSpacing,
    color: color ?? const Color(0xFF6B7280),
  );

  static TextStyle technical({
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 0.3,
  }) => TextStyle(
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

  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.primary,
    onPrimary: colors.onPrimary,
    primaryContainer: colors.accent.withValues(alpha: 0.18),
    onPrimaryContainer: colors.primaryText,
    secondary: colors.accent,
    onSecondary: colors.onPrimary,
    secondaryContainer: colors.accent.withValues(alpha: 0.16),
    onSecondaryContainer: colors.primaryText,
    tertiary: colors.tertiary,
    onTertiary: colors.onPrimary,
    error: colors.danger,
    onError: colors.onPrimary,
    surface: colors.surface,
    onSurface: colors.primaryText,
    surfaceContainerHighest: colors.surface2,
    onSurfaceVariant: colors.secondaryText,
    outline: colors.divider,
    outlineVariant: colors.divider,
    shadow: Colors.transparent,
    scrim: Colors.black,
    inverseSurface: colors.surface2,
    onInverseSurface: colors.primaryText,
    inversePrimary: colors.accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.background,
    canvasColor: colors.background,
    colorScheme: scheme,
    splashFactory: InkSparkle.splashFactory,
    extensions: [colors],
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accent.withValues(alpha: 0.30),
      selectionHandleColor: colors.accent,
    ),
    textTheme: TextTheme(
      displaySmall: SpaceTypography.display(color: colors.primaryText),
      headlineSmall: SpaceTypography.headingLarge(color: colors.primaryText),
      titleLarge: SpaceTypography.headingMedium(color: colors.primaryText),
      titleMedium: SpaceTypography.headingSmall(color: colors.primaryText),
      bodyLarge: SpaceTypography.bodyLarge(color: colors.primaryText),
      bodyMedium: SpaceTypography.bodyMedium(color: colors.secondaryText),
      bodySmall: SpaceTypography.bodySmall(color: colors.muted),
      labelLarge: SpaceTypography.bodyMedium(
        color: colors.primaryText,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: SpaceTypography.caption(color: colors.secondaryText),
      labelSmall: SpaceTypography.technical(color: colors.muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.primaryText,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      titleTextStyle: SpaceTypography.headingMedium(color: colors.primaryText),
      iconTheme: IconThemeData(color: colors.secondaryText, size: 24),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.primary,
        foregroundColor: colors.onPrimary,
        disabledBackgroundColor: colors.surface2,
        disabledForegroundColor: colors.muted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.primaryText,
        disabledForegroundColor: colors.muted,
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        side: BorderSide(color: colors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        disabledForegroundColor: colors.muted,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.secondaryText,
        disabledForegroundColor: colors.muted,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surface2,
      hintStyle: SpaceTypography.bodyMedium(color: colors.muted),
      labelStyle: SpaceTypography.bodyMedium(color: colors.secondaryText),
      floatingLabelStyle: SpaceTypography.bodyMedium(color: colors.accent),
      helperStyle: SpaceTypography.bodySmall(color: colors.muted),
      errorStyle: SpaceTypography.bodySmall(color: colors.danger),
      counterStyle: SpaceTypography.technical(color: colors.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.accent, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.danger, width: 1.6),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.muted,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: colors.accent,
      inactiveTrackColor: colors.divider,
      thumbColor: colors.accent,
      overlayColor: colors.accent.withValues(alpha: 0.10),
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
    dividerTheme: DividerThemeData(
      color: colors.divider,
      thickness: 1,
      space: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      titleTextStyle: SpaceTypography.headingMedium(color: colors.primaryText),
      contentTextStyle: SpaceTypography.bodyMedium(color: colors.secondaryText),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: colors.divider,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.surface2,
      contentTextStyle: SpaceTypography.bodyMedium(color: colors.primaryText),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.all(16),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.navBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: colors.accent.withValues(alpha: 0.16),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? colors.accent
              : colors.muted,
          size: 24,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? SpaceTypography.caption(
                color: colors.accent,
                fontWeight: FontWeight.w600,
              )
            : SpaceTypography.caption(color: colors.muted),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.divider,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: colors.surface2),
      textStyle: SpaceTypography.caption(color: colors.primaryText),
      waitDuration: const Duration(milliseconds: 400),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.primary,
      foregroundColor: colors.onPrimary,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      disabledElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      extendedTextStyle: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: SpaceTypography.bodyMedium(color: colors.primaryText),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.secondaryText,
      textColor: colors.primaryText,
    ),
  );
}