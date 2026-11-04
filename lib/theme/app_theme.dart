import 'package:flutter/material.dart';

import 'palette.dart';

/// Material 3 motion tokens (durations from [Durations], easing from [Easing]).
class Motion {
  static const short = Durations.short4; // 200ms
  static const medium = Durations.medium2; // 300ms
  static const long = Durations.long2; // 500ms
  static const Curve enter = Easing.emphasizedDecelerate;
  static const Curve exit = Easing.emphasizedAccelerate;
  static const Curve standard = Easing.standard;

  /// Collapses durations to zero when the user asked the OS to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Colours that have no Material role: the heat-map ramp.
@immutable
class CozyColors extends ThemeExtension<CozyColors> {
  const CozyColors({required this.heat});

  final List<Color> heat;

  static CozyColors of(BuildContext context) =>
      Theme.of(context).extension<CozyColors>()!;

  @override
  CozyColors copyWith({List<Color>? heat}) =>
      CozyColors(heat: heat ?? this.heat);

  @override
  CozyColors lerp(CozyColors? other, double t) {
    if (other == null) return this;
    return CozyColors(
      heat: [
        for (var i = 0; i < heat.length; i++)
          Color.lerp(heat[i], other.heat[i], t)!,
      ],
    );
  }
}

/// The app theme: dark, brown, and as close to stock Material 3 as possible.
/// Component styling is left to Flutter's M3 defaults (which are generated
/// from the official M3 tokens); only genuine preferences are overridden.
ThemeData buildTheme() {
  final scheme = BrownScheme.colorScheme();
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
  );

  // Type: Nunito (rounded humanist sans, very readable) for the M3 type scale;
  // Fraunces (soft old-style serif) only for display/headline roles — the M3
  // "brand typeface for expressive moments" pattern.
  final plain = base.textTheme.apply(
    fontFamily: 'Nunito',
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  TextStyle? brand(TextStyle? s) =>
      s?.copyWith(fontFamily: 'Fraunces', fontWeight: FontWeight.w600);
  final text = plain.copyWith(
    displayLarge: brand(plain.displayLarge),
    displayMedium: brand(plain.displayMedium),
    displaySmall: brand(plain.displaySmall),
    headlineLarge: brand(plain.headlineLarge),
    headlineMedium: brand(plain.headlineMedium),
    headlineSmall: brand(plain.headlineSmall),
    // Nunito's regular weight is light; M3 titles are "medium" (500).
    titleLarge: plain.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: plain.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    titleSmall: plain.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: plain.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    labelMedium: plain.labelMedium?.copyWith(fontWeight: FontWeight.w600),
    labelSmall: plain.labelSmall?.copyWith(fontWeight: FontWeight.w600),
  );

  return base.copyWith(
    textTheme: text,
    extensions: [CozyColors(heat: BrownScheme.heat(scheme))],
    cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(filled: true),
    // Opt into the current (2024) M3 progress indicator and slider specs.
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}
