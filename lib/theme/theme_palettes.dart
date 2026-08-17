import 'package:flutter/material.dart';

import 'harvest_palette.dart';

/// A named look for the whole interface: an accent plus the light and dark
/// surface/ink sets built around it.
///
/// The original Grain palette is spelled out by hand — its warm-paper light
/// mode and cool-gray dark mode were tuned rather than computed — while the
/// rest are derived from a short spec by [_derive], so adding one means
/// choosing four colours instead of twenty-six.
@immutable
class GrainThemePalette {
  /// Stable key persisted in preferences. Never reuse or rename one.
  final String id;
  final String label;
  final String description;
  final HarvestPalette light;
  final HarvestPalette dark;

  const GrainThemePalette({
    required this.id,
    required this.label,
    required this.description,
    required this.light,
    required this.dark,
  });

  HarvestPalette forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The accent, for a preview swatch that has no theme to read from.
  Color get accent => light.brand;
}

/// Every palette on offer, in the order the settings picker shows them.
/// Not `const`: all but Grain are computed by [_derive].
final kThemePalettes = <GrainThemePalette>[
  _grain,
  _modernSlate,
  _deepIndigo,
  _emeraldEarth,
  _warmSand,
];

const kDefaultThemePaletteId = 'grain';

/// The palette for [id], falling back to the default when it is unknown —
/// a stored id outlives the palette it named if one is ever removed.
GrainThemePalette themePaletteById(String? id) {
  for (final palette in kThemePalettes) {
    if (palette.id == id) return palette;
  }
  return kThemePalettes.first;
}

// ── Grain ────────────────────────────────────────────────────────────────
// The original: warm paper in light, neutral gray with a faint cool tint in
// dark, brand orange as the single confident accent.

const _grain = GrainThemePalette(
  id: kDefaultThemePaletteId,
  label: 'Grain',
  description: 'Warm paper and brand orange',
  light: HarvestPalette(
    bg: Color(0xFFF6F3EE),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFFBF8F3),
    surface3: Color(0xFFF1ECE3),
    border: Color(0xFFE8E1D4),
    borderStrong: Color(0xFFD5CCBB),
    divider: Color(0xFFEFEAE0),
    text: Color(0xFF1A1814),
    text2: Color(0xFF56504A),
    text3: Color(0xFF8A837A),
    text4: Color(0xFFB4AEA4),
    brandTint: Color(0xFFFEE6DA),
    brandTint2: Color(0xFFFDD3BD),
    brand: Color(0xFFFA5D24),
    brand600: Color(0xFFE54714),
  ),
  dark: HarvestPalette(
    bg: Color(0xFF2A2C2F),
    surface: Color(0xFF2F3134),
    surface2: Color(0xFF36383C),
    surface3: Color(0xFF3E4145),
    border: Color(0xFF44474C),
    borderStrong: Color(0xFF5A5E64),
    divider: Color(0xFF34363A),
    text: Color(0xFFE6E8EA),
    text2: Color(0xFFAEB2B8),
    text3: Color(0xFF7A7E84),
    text4: Color(0xFF55585D),
    brandTint: Color(0xFF42261A),
    brandTint2: Color(0xFF5E3826),
    brand: Color(0xFFFA5D24),
    brand600: Color(0xFFE54714),
  ),
);

// ── Derived palettes ─────────────────────────────────────────────────────

final _modernSlate = _derive(
  id: 'modern_slate',
  label: 'Modern Slate',
  description: 'Cool neutrals, near-black accent',
  accent: const Color(0xFF0F172A),
  accentOnDark: const Color(0xFF94A3B8),
  lightBg: const Color(0xFFF8FAFC),
  lightSurface: const Color(0xFFFFFFFF),
  darkBg: const Color(0xFF090D16),
  darkSurface: const Color(0xFF1E293B),
  lightInk: const Color(0xFF0F172A),
  darkInk: const Color(0xFFE2E8F0),
);

final _deepIndigo = _derive(
  id: 'deep_indigo',
  label: 'Deep Indigo',
  description: 'Indigo accent on cool gray',
  accent: const Color(0xFF4F46E5),
  accentOnDark: const Color(0xFF818CF8),
  lightBg: const Color(0xFFF9FAFB),
  lightSurface: const Color(0xFFFFFFFF),
  darkBg: const Color(0xFF0F172A),
  darkSurface: const Color(0xFF1F2937),
  lightInk: const Color(0xFF111827),
  darkInk: const Color(0xFFE5E7EB),
);

final _emeraldEarth = _derive(
  id: 'emerald_earth',
  label: 'Emerald Earth',
  description: 'Emerald accent on soft green-gray',
  accent: const Color(0xFF059669),
  accentOnDark: const Color(0xFF34D399),
  lightBg: const Color(0xFFF4F6F4),
  lightSurface: const Color(0xFFFFFFFF),
  darkBg: const Color(0xFF0C1410),
  darkSurface: const Color(0xFF18241D),
  lightInk: const Color(0xFF10241A),
  darkInk: const Color(0xFFE3EAE5),
);

final _warmSand = _derive(
  id: 'warm_sand',
  label: 'Warm Sand',
  description: 'Amber accent on warm stone',
  accent: const Color(0xFFD97706),
  accentOnDark: const Color(0xFFFBBF24),
  lightBg: const Color(0xFFFAFAF9),
  lightSurface: const Color(0xFFFFFFFF),
  darkBg: const Color(0xFF1C1917),
  darkSurface: const Color(0xFF292524),
  lightInk: const Color(0xFF1C1917),
  darkInk: const Color(0xFFE7E5E4),
);

/// Builds both variants from the handful of colours that actually distinguish
/// a palette. The surface steps, strokes and ink ramp are mixed from the
/// background and ink so every palette keeps the same contrast relationships
/// the hand-tuned Grain one has.
GrainThemePalette _derive({
  required String id,
  required String label,
  required String description,
  required Color accent,

  /// A lighter accent for dark mode — the light-mode accent is often too dark
  /// to read as an accent on a dark canvas.
  required Color accentOnDark,
  required Color lightBg,
  required Color lightSurface,
  required Color darkBg,
  required Color darkSurface,
  required Color lightInk,
  required Color darkInk,
}) {
  Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  final lightPalette = HarvestPalette(
    bg: lightBg,
    surface: lightSurface,
    surface2: mix(lightSurface, lightBg, 0.6),
    surface3: mix(lightBg, lightInk, 0.06),
    border: mix(lightBg, lightInk, 0.13),
    borderStrong: mix(lightBg, lightInk, 0.28),
    divider: mix(lightBg, lightInk, 0.08),
    text: lightInk,
    text2: mix(lightInk, lightBg, 0.32),
    text3: mix(lightInk, lightBg, 0.48),
    text4: mix(lightInk, lightBg, 0.66),
    brandTint: mix(lightSurface, accent, 0.14),
    brandTint2: mix(lightSurface, accent, 0.3),
    brand: accent,
    brand600: mix(accent, Colors.black, 0.12),
  );

  final darkPalette = HarvestPalette(
    bg: darkBg,
    surface: darkSurface,
    surface2: mix(darkSurface, darkInk, 0.07),
    surface3: mix(darkSurface, darkInk, 0.14),
    border: mix(darkSurface, darkInk, 0.2),
    borderStrong: mix(darkSurface, darkInk, 0.36),
    divider: mix(darkSurface, darkInk, 0.1),
    text: darkInk,
    text2: mix(darkInk, darkBg, 0.30),
    text3: mix(darkInk, darkBg, 0.48),
    text4: mix(darkInk, darkBg, 0.66),
    brandTint: mix(darkSurface, accentOnDark, 0.22),
    brandTint2: mix(darkSurface, accentOnDark, 0.38),
    brand: accentOnDark,
    brand600: mix(accentOnDark, Colors.white, 0.15),
  );

  return GrainThemePalette(
    id: id,
    label: label,
    description: description,
    light: lightPalette,
    dark: darkPalette,
  );
}
