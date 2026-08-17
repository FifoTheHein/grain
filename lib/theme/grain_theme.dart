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
    colorScheme: ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: brightness,
      surface: palette.surface,
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
