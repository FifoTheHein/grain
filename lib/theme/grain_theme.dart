import 'package:flutter/material.dart';

import 'harvest_palette.dart';
import 'harvest_tokens.dart';

ThemeData buildGrainTheme(Brightness brightness) {
  final palette =
      brightness == Brightness.dark ? HarvestPalette.dark : HarvestPalette.light;
  return ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: HarvestTokens.brand,
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
