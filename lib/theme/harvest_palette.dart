import 'package:flutter/material.dart';

@immutable
class HarvestPalette extends ThemeExtension<HarvestPalette> {
  final Color bg;
  final Color surface;
  final Color surface2;
  final Color surface3;
  final Color border;
  final Color borderStrong;
  final Color divider;
  final Color text;
  final Color text2;
  final Color text3;
  final Color text4;
  final Color brandTint;
  final Color brandTint2;

  const HarvestPalette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.border,
    required this.borderStrong,
    required this.divider,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.brandTint,
    required this.brandTint2,
  });

  static const light = HarvestPalette(
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
  );

  // Dark palette: neutral gray with a faint cool tint (Fork / VS Code vibe).
  // S ≈ 4%, hue ~215° — reads as clean gray, not "almost blue", and lets
  // the brand orange land as the single confident accent on canvas.
  // Surface steps ~3-4% L apart for crisp hierarchy on any monitor.
  // Text contrast on bg ≈ 11:1 (primary), 6:1 (secondary), 4:1 (tertiary).
  static const dark = HarvestPalette(
    bg: Color(0xFF2A2C2F),          // canvas
    surface: Color(0xFF2F3134),     // card
    surface2: Color(0xFF36383C),    // raised card
    surface3: Color(0xFF3E4145),    // input / chip background
    border: Color(0xFF44474C),      // subtle stroke
    borderStrong: Color(0xFF5A5E64), // emphasized stroke
    divider: Color(0xFF34363A),     // hairline
    text: Color(0xFFE6E8EA),        // primary
    text2: Color(0xFFAEB2B8),       // secondary
    text3: Color(0xFF7A7E84),       // tertiary
    text4: Color(0xFF55585D),       // disabled / icon faint
    brandTint: Color(0xFF42261A),   // brand-tinted bg pill
    brandTint2: Color(0xFF5E3826),  // brand-tinted bg pill — stronger
  );

  @override
  HarvestPalette copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? surface3,
    Color? border,
    Color? borderStrong,
    Color? divider,
    Color? text,
    Color? text2,
    Color? text3,
    Color? text4,
    Color? brandTint,
    Color? brandTint2,
  }) =>
      HarvestPalette(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        surface3: surface3 ?? this.surface3,
        border: border ?? this.border,
        borderStrong: borderStrong ?? this.borderStrong,
        divider: divider ?? this.divider,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        text3: text3 ?? this.text3,
        text4: text4 ?? this.text4,
        brandTint: brandTint ?? this.brandTint,
        brandTint2: brandTint2 ?? this.brandTint2,
      );

  @override
  HarvestPalette lerp(ThemeExtension<HarvestPalette>? other, double t) {
    if (other is! HarvestPalette) return this;
    return HarvestPalette(
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      surface3: Color.lerp(surface3, other.surface3, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      text: Color.lerp(text, other.text, t)!,
      text2: Color.lerp(text2, other.text2, t)!,
      text3: Color.lerp(text3, other.text3, t)!,
      text4: Color.lerp(text4, other.text4, t)!,
      brandTint: Color.lerp(brandTint, other.brandTint, t)!,
      brandTint2: Color.lerp(brandTint2, other.brandTint2, t)!,
    );
  }
}
