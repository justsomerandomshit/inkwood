import 'package:flutter/material.dart';
import 'package:material_color_utilities/material_color_utilities.dart';

/// Inkwood's colour system: an oak hut at night, entirely in shades of brown.
///
/// Built the Material 3 way: five HCT tonal palettes feed a [DynamicScheme],
/// and every colour role (surfaces, containers, text, outlines) is the
/// spec-defined tone of one of those palettes. This keeps all M3 contrast
/// guarantees (≥ 4.5:1 for text roles) while staying in one hue family.
///
/// * **Hue:** all palettes share the oak hue of [seed]; the tertiary palette
///   leans a few degrees toward red (chestnut) and error further still (rust)
///   so they remain distinguishable without leaving the brown family.
/// * **Chroma:** primary is the richest (polished oak), secondary is muted
///   (weathered wood), neutrals keep a little chroma so dark surfaces read as
///   walnut/espresso rather than grey.
/// * **Dark only:** surfaces sit at M3's dark tones (6–22). Text roles are
///   necessarily light tones of the same brown palettes (tan/cream) — the
///   minimum needed for readable contrast.
class BrownScheme {
  BrownScheme._();

  /// Oak.
  static const seed = Color(0xFF7A4E2D);

  static final DynamicScheme dynamic = _build();

  static DynamicScheme _build() {
    final source = Hct.fromInt(seed.toARGB32());
    final h = source.hue;
    return DynamicScheme(
      sourceColorHct: source,
      variant: Variant.tonalSpot,
      isDark: true,
      primaryPalette: TonalPalette.of(h + 8, 24),
      secondaryPalette: TonalPalette.of(h, 14),
      tertiaryPalette: TonalPalette.of(h - 12, 22),
      neutralPalette: TonalPalette.of(h, 10),
      neutralVariantPalette: TonalPalette.of(h, 16),
      errorPalette: TonalPalette.of(h - 28, 56),
    );
  }

  static ColorScheme colorScheme() {
    final s = dynamic;
    Color c(DynamicColor d) => Color(d.getArgb(s));
    return ColorScheme(
      brightness: Brightness.dark,
      primary: c(MaterialDynamicColors.primary),
      onPrimary: c(MaterialDynamicColors.onPrimary),
      primaryContainer: c(MaterialDynamicColors.primaryContainer),
      onPrimaryContainer: c(MaterialDynamicColors.onPrimaryContainer),
      primaryFixed: c(MaterialDynamicColors.primaryFixed),
      primaryFixedDim: c(MaterialDynamicColors.primaryFixedDim),
      onPrimaryFixed: c(MaterialDynamicColors.onPrimaryFixed),
      onPrimaryFixedVariant: c(MaterialDynamicColors.onPrimaryFixedVariant),
      secondary: c(MaterialDynamicColors.secondary),
      onSecondary: c(MaterialDynamicColors.onSecondary),
      secondaryContainer: c(MaterialDynamicColors.secondaryContainer),
      onSecondaryContainer: c(MaterialDynamicColors.onSecondaryContainer),
      secondaryFixed: c(MaterialDynamicColors.secondaryFixed),
      secondaryFixedDim: c(MaterialDynamicColors.secondaryFixedDim),
      onSecondaryFixed: c(MaterialDynamicColors.onSecondaryFixed),
      onSecondaryFixedVariant: c(MaterialDynamicColors.onSecondaryFixedVariant),
      tertiary: c(MaterialDynamicColors.tertiary),
      onTertiary: c(MaterialDynamicColors.onTertiary),
      tertiaryContainer: c(MaterialDynamicColors.tertiaryContainer),
      onTertiaryContainer: c(MaterialDynamicColors.onTertiaryContainer),
      tertiaryFixed: c(MaterialDynamicColors.tertiaryFixed),
      tertiaryFixedDim: c(MaterialDynamicColors.tertiaryFixedDim),
      onTertiaryFixed: c(MaterialDynamicColors.onTertiaryFixed),
      onTertiaryFixedVariant: c(MaterialDynamicColors.onTertiaryFixedVariant),
      error: c(MaterialDynamicColors.error),
      onError: c(MaterialDynamicColors.onError),
      errorContainer: c(MaterialDynamicColors.errorContainer),
      onErrorContainer: c(MaterialDynamicColors.onErrorContainer),
      surface: c(MaterialDynamicColors.surface),
      onSurface: c(MaterialDynamicColors.onSurface),
      surfaceDim: c(MaterialDynamicColors.surfaceDim),
      surfaceBright: c(MaterialDynamicColors.surfaceBright),
      surfaceContainerLowest: c(MaterialDynamicColors.surfaceContainerLowest),
      surfaceContainerLow: c(MaterialDynamicColors.surfaceContainerLow),
      surfaceContainer: c(MaterialDynamicColors.surfaceContainer),
      surfaceContainerHigh: c(MaterialDynamicColors.surfaceContainerHigh),
      surfaceContainerHighest: c(MaterialDynamicColors.surfaceContainerHighest),
      onSurfaceVariant: c(MaterialDynamicColors.onSurfaceVariant),
      outline: c(MaterialDynamicColors.outline),
      outlineVariant: c(MaterialDynamicColors.outlineVariant),
      shadow: c(MaterialDynamicColors.shadow),
      scrim: c(MaterialDynamicColors.scrim),
      inverseSurface: c(MaterialDynamicColors.inverseSurface),
      onInverseSurface: c(MaterialDynamicColors.inverseOnSurface),
      inversePrimary: c(MaterialDynamicColors.inversePrimary),
      surfaceTint: c(MaterialDynamicColors.surfaceTint),
    );
  }

  /// Sequential heat ramp: empty day, then four rising tones of the primary
  /// (oak) palette. Luminance increases monotonically, so it also reads in
  /// greyscale and for colour-blind users.
  static List<Color> heat(ColorScheme cs) {
    final p = dynamic.primaryPalette;
    return [
      cs.surfaceContainerHigh,
      Color(p.get(25)),
      Color(p.get(34)),
      Color(p.get(44)),
      Color(p.get(56)),
    ];
  }
}
