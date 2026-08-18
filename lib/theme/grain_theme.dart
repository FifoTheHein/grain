import 'package:flutter/material.dart';

import 'theme_palettes.dart';

/// Builds the app theme for [brightness] from the chosen [themePalette],
/// defaulting to Grain's own.
ThemeData buildGrainTheme(
  Brightness brightness, [
  GrainThemePalette? themePalette,
]) {
  final palette =
      (themePalette ?? kThemePalettes.first).forBrightness(brightness);
  return ThemeData(
    brightness: brightness,
    // fromSeed derives a *tonal* primary from the seed, which is close to the
    // accent but not it — that left Material widgets (the selected day chip,
    // filled buttons) painting a colour the palette never chose. Pin the
    // accent and its ink so anything reading colorScheme matches.
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: brightness,
      surface: palette.surface,
    ).copyWith(
      primary: palette.brand,
      onPrimary: palette.onBrand,
      secondary: palette.brand,
      onSecondary: palette.onBrand,
    ),
    scaffoldBackgroundColor: palette.bg,
    cardTheme: CardThemeData(
      color: palette.surface,
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: palette.border),
      ),
    ),
    dividerColor: palette.divider,
    useMaterial3: true,
    extensions: [palette],
  );
}
