import 'package:flutter/material.dart';

/// Spacing scale -- used everywhere instead of ad-hoc EdgeInsets numbers,
/// so padding and gaps stay visually uniform across screens.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Corner-rounding scale. Soft, rounded-everything (cards, inputs, pills,
/// sheets) is the main shape signature of the theme, applied uniformly.
class AppRadius {
  const AppRadius._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Lolly.ai's visual identity, "Midnight Bloom" (2026-10-11 redesign).
///
/// Dark-only, on purpose: the app is about *hearing* someone before you
/// see them, and a late-night, low-light canvas is where voices feel
/// close. Every screen sits on [ink]; colour is spent sparingly and loud:
///
///  - **Bloom gradient** ([magenta] -> [coral] -> [amber], see
///    `bloomGradient` in branding.dart): the brand. Fills the single
///    primary action per screen (GradientButton), selected choices, and
///    hero moments (match, reveal).
///  - **Violet** ([plum]): ambient glow only -- the aurora behind screens.
///  - **Coral** ([coral]): the voice. Waveforms, the mark's lollipop head.
///
/// Type is Plus Jakarta Sans (bundled, OFL -- assets/fonts/OFL.txt):
/// tight, heavy headlines; relaxed body copy.
///
/// Single source of truth: expand here rather than hardcoding styles per
/// widget. android/.../values/colors.xml must match [ink]/[magenta].
class AppTheme {
  const AppTheme._();

  static const String fontFamily = 'PlusJakartaSans';

  // Brand.
  static const Color plum = Color(0xFF7C3AED);
  static const Color magenta = Color(0xFFFF2E93);
  static const Color coral = Color(0xFFFF5E62);
  static const Color coralLight = Color(0xFFFF8A80);
  static const Color amber = Color(0xFFFF9A44);
  static const Color peach = Color(0xFFFFC9B5);
  static const Color coralDeep = Color(0xFF5A1A2E);

  // Canvas.
  static const Color ink = Color(0xFF0C0911);
  static const Color surface1 = Color(0xFF15111C);
  static const Color surface2 = Color(0xFF1D1726);
  static const Color surface3 = Color(0xFF272032);
  static const Color stroke = Color(0x1FFFFFFF);
  static const Color textPrimary = Color(0xFFF7F3FA);
  static const Color textMuted = Color(0xFFA79FB4);

  /// Kept for call sites that still pick by brightness; both are the
  /// same dark theme now (see class doc).
  static ThemeData get light => _build();
  static ThemeData get dark => _build();

  /// Solid fallback for a primary call-to-action that can't use
  /// GradientButton (e.g. inside a dialog).
  static ButtonStyle accentButton(ColorScheme scheme) => FilledButton.styleFrom(
        backgroundColor: magenta,
        foregroundColor: Colors.white,
        disabledBackgroundColor: surface3,
        disabledForegroundColor: textMuted,
      );

  static ThemeData _build() {
    final scheme = ColorScheme.fromSeed(
      seedColor: magenta,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.vibrant,
    ).copyWith(
      primary: magenta,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFF4A1233),
      onPrimaryContainer: const Color(0xFFFFD1E6),
      secondary: plum,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFF2E1A52),
      onSecondaryContainer: const Color(0xFFE4D6FF),
      tertiary: coral,
      onTertiary: Colors.white,
      tertiaryContainer: coralDeep,
      onTertiaryContainer: peach,
      surface: ink,
      onSurface: textPrimary,
      onSurfaceVariant: textMuted,
      surfaceContainerLowest: ink,
      surfaceContainerLow: surface1,
      surfaceContainer: surface2,
      surfaceContainerHigh: surface3,
      surfaceContainerHighest: const Color(0xFF30283C),
      outline: const Color(0x40FFFFFF),
      outlineVariant: stroke,
      error: const Color(0xFFFF6B81),
      onError: Colors.white,
    );

    final base = Typography.material2021(platform: TargetPlatform.android).white.apply(
          fontFamily: fontFamily,
          bodyColor: textPrimary,
          displayColor: textPrimary,
        );
    final textTheme = base.copyWith(
      displayMedium: base.displayMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.6, height: 1.05),
      displaySmall: base.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.2, height: 1.1),
      headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1.0, height: 1.12),
      headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.15),
      headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
      titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(height: 1.45, color: textMuted),
      bodySmall: base.bodySmall?.copyWith(height: 1.4, color: textMuted),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.1),
    );

    SoftFieldBorder border(Color color, [double width = 1]) => SoftFieldBorder(
          borderRadius: BorderRadius.circular(AppRadius.md + 2),
          borderSide: BorderSide(color: color, width: width),
        );

    const pillPadding = EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md);
    const pillText = TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700, fontSize: 16);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: ink,
      canvasColor: ink,
      visualDensity: VisualDensity.comfortable,
      splashFactory: InkSparkle.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: FadeForwardsPageTransitionsBuilder()},
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: textPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surface1,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: stroke),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        contentPadding: const EdgeInsets.fromLTRB(AppSpacing.md + 4, 14, AppSpacing.md + 4, 14),
        border: border(Colors.transparent),
        enabledBorder: border(Colors.transparent),
        focusedBorder: border(magenta, 1.6),
        errorBorder: border(scheme.error),
        focusedErrorBorder: border(scheme.error, 1.6),
        labelStyle: const TextStyle(color: textMuted),
        floatingLabelStyle: const TextStyle(color: magenta, fontWeight: FontWeight.w600),
        hintStyle: TextStyle(color: textMuted.withValues(alpha: 0.6)),
        prefixIconColor: textMuted,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: magenta,
        selectionColor: magenta.withValues(alpha: 0.35),
        selectionHandleColor: magenta,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          padding: pillPadding,
          shape: const StadiumBorder(),
          backgroundColor: magenta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: surface3,
          disabledForegroundColor: textMuted,
          textStyle: pillText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          padding: pillPadding,
          shape: const StadiumBorder(),
          side: const BorderSide(color: Color(0x33FFFFFF)),
          foregroundColor: textPrimary,
          backgroundColor: Colors.white.withValues(alpha: 0.04),
          textStyle: pillText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: coralLight,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: textPrimary),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: const StadiumBorder()),
      ),
      chipTheme: const ChipThemeData(
        shape: StadiumBorder(side: BorderSide(color: stroke)),
        side: BorderSide(color: stroke),
        backgroundColor: surface2,
        selectedColor: Color(0xFF4A1233),
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, color: textPrimary),
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 6,
        activeTrackColor: magenta,
        inactiveTrackColor: surface3,
        thumbColor: Colors.white,
        overlayColor: magenta.withValues(alpha: 0.18),
        rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 13, elevation: 4),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 13, elevation: 4),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        rangeTickMarkShape: const RoundRangeSliderTickMarkShape(tickMarkRadius: 0),
        showValueIndicator: ShowValueIndicator.never,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : textMuted),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? magenta : surface3),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: magenta,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: Color(0x40FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: const BorderSide(color: stroke),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface2,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: surface3,
        contentTextStyle: const TextStyle(fontFamily: fontFamily, color: textPrimary, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface1,
        surfaceTintColor: Colors.transparent,
        indicatorColor: const Color(0xFF4A1233),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontFamily: fontFamily, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ),
      dividerTheme: const DividerThemeData(color: stroke, space: 1),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: magenta, linearTrackColor: surface3),
      radioTheme: RadioThemeData(fillColor: WidgetStateProperty.all(magenta)),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? magenta : null),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xs)),
      ),
    );
  }
}

/// Text-field border for the filled dark fields: a full rounded outline
/// (focus ring) with NO notch cut for the label, and the floating label
/// kept *inside* the field, Material-3-filled style. Stock
/// OutlineInputBorder floats the label onto the outline and cuts a gap
/// around it, which reads as a broken border on a filled field.
class SoftFieldBorder extends OutlineInputBorder {
  const SoftFieldBorder({super.borderSide, super.borderRadius});

  /// Not an "outline" to InputDecorator: label floats inside, no gap.
  @override
  bool get isOutline => false;

  @override
  SoftFieldBorder copyWith({BorderSide? borderSide, BorderRadius? borderRadius, double? gapPadding}) =>
      SoftFieldBorder(borderSide: borderSide ?? this.borderSide, borderRadius: borderRadius ?? this.borderRadius);

  @override
  SoftFieldBorder scale(double t) =>
      SoftFieldBorder(borderSide: borderSide.scale(t), borderRadius: borderRadius * t);

  // Keep the type through the focus animation, so the label never flips
  // to outline placement mid-transition.
  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is SoftFieldBorder) {
      return SoftFieldBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is SoftFieldBorder) {
      return SoftFieldBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (borderSide.style == BorderStyle.none || borderSide.width == 0) return;
    final rrect = borderRadius.resolve(textDirection).toRRect(rect).deflate(borderSide.width / 2);
    canvas.drawRRect(rrect, borderSide.toPaint());
  }
}
