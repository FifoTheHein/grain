import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/theme/theme_palettes.dart';

/// Relative luminance, for asserting a palette's ink actually contrasts with
/// its canvas rather than merely differing from it.
double _luminance(Color c) => c.computeLuminance();

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('catalogue', () {
    test('Grain is first, so it stays the default', () {
      expect(kThemePalettes.first.id, kDefaultThemePaletteId);
      expect(kThemePalettes.first.label, 'Grain');
    });

    test('ids are unique — they are persisted keys', () {
      final ids = kThemePalettes.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every palette is labelled and described', () {
      for (final p in kThemePalettes) {
        expect(p.label.trim(), isNotEmpty, reason: p.id);
        expect(p.description.trim(), isNotEmpty, reason: p.id);
      }
    });

    test('the four requested palettes are present', () {
      final ids = kThemePalettes.map((p) => p.id);
      expect(
        ids,
        containsAll(
            ['modern_slate', 'deep_indigo', 'emerald_earth', 'warm_sand']),
      );
    });
  });

  group('themePaletteById', () {
    test('finds each palette by its id', () {
      for (final p in kThemePalettes) {
        expect(themePaletteById(p.id).id, p.id);
      }
    });

    test('an unknown or missing id falls back to the default', () {
      // A stored id outlives the palette it named if one is ever removed.
      expect(themePaletteById('retired_palette').id, kDefaultThemePaletteId);
      expect(themePaletteById(null).id, kDefaultThemePaletteId);
      expect(themePaletteById('').id, kDefaultThemePaletteId);
    });
  });

  group('forBrightness', () {
    test('returns the matching variant', () {
      for (final p in kThemePalettes) {
        expect(p.forBrightness(Brightness.light), same(p.light));
        expect(p.forBrightness(Brightness.dark), same(p.dark));
      }
    });

    test('light and dark actually differ', () {
      for (final p in kThemePalettes) {
        expect(p.light.bg, isNot(p.dark.bg), reason: p.id);
        expect(p.light.text, isNot(p.dark.text), reason: p.id);
      }
    });
  });

  group('every palette is usable', () {
    test('dark mode is darker than light mode', () {
      for (final p in kThemePalettes) {
        expect(_luminance(p.dark.bg), lessThan(_luminance(p.light.bg)),
            reason: p.id);
      }
    });

    test('body text clears 7:1 against the canvas', () {
      for (final p in kThemePalettes) {
        expect(_contrast(p.light.text, p.light.bg), greaterThan(7.0),
            reason: '${p.id} light');
        expect(_contrast(p.dark.text, p.dark.bg), greaterThan(7.0),
            reason: '${p.id} dark');
      }
    });

    test('secondary and tertiary ink stay legible', () {
      for (final p in kThemePalettes) {
        expect(_contrast(p.light.text2, p.light.bg), greaterThan(4.5),
            reason: '${p.id} light text2');
        expect(_contrast(p.dark.text2, p.dark.bg), greaterThan(4.5),
            reason: '${p.id} dark text2');
        expect(_contrast(p.light.text3, p.light.bg), greaterThan(3.0),
            reason: '${p.id} light text3');
        expect(_contrast(p.dark.text3, p.dark.bg), greaterThan(3.0),
            reason: '${p.id} dark text3');
      }
    });

    test('the accent is visible against its own tint', () {
      // The tint is used as a pill behind accent-coloured text.
      for (final p in kThemePalettes) {
        expect(_contrast(p.light.brand600, p.light.brandTint),
            greaterThan(3.0),
            reason: '${p.id} light');
        expect(_contrast(p.dark.brand600, p.dark.brandTint), greaterThan(3.0),
            reason: '${p.id} dark');
      }
    });

    test('surfaces are distinguishable from the canvas', () {
      for (final p in kThemePalettes) {
        expect(p.light.surface, isNot(p.light.bg), reason: '${p.id} light');
        expect(p.dark.surface, isNot(p.dark.bg), reason: '${p.id} dark');
      }
    });

    test('the ink ramp fades in one direction', () {
      for (final p in kThemePalettes) {
        final light = [
          _contrast(p.light.text, p.light.bg),
          _contrast(p.light.text2, p.light.bg),
          _contrast(p.light.text3, p.light.bg),
          _contrast(p.light.text4, p.light.bg),
        ];
        expect(light, orderedEquals(([...light]..sort((a, b) => b.compareTo(a)))),
            reason: '${p.id} light ramp should weaken monotonically');
      }
    });
  });

  group('onBrand', () {
    test('clears the 3:1 floor for large UI text on every palette', () {
      // The app bar, filled buttons and the running pill paint text in this
      // colour over a brand fill. Grain's white-on-orange sits at 3.16:1 — it
      // predates the palettes and is deliberately left as it is, so 3:1 (the
      // WCAG floor for large text and UI components) is the bar here.
      for (final p in kThemePalettes) {
        expect(_contrast(p.light.onBrand, p.light.brand), greaterThan(3.0),
            reason: '${p.id} light');
        expect(_contrast(p.dark.onBrand, p.dark.brand), greaterThan(3.0),
            reason: '${p.id} dark');
      }
    });

    test('the derived palettes clear 4.5:1, since nothing constrains them', () {
      // White over Warm Sand's amber was 1.8:1 — the unreadable header.
      for (final p in kThemePalettes.where((p) => p.id != 'grain')) {
        expect(_contrast(p.light.onBrand, p.light.brand), greaterThan(4.5),
            reason: '${p.id} light');
        expect(_contrast(p.dark.onBrand, p.dark.brand), greaterThan(4.5),
            reason: '${p.id} dark');
      }
    });

    test('is whichever ink contrasts more with the accent', () {
      // Not a luminance threshold: a mid-tone accent falls on the wrong side
      // of any fixed cut-off, so the better of the two candidates wins.
      // Grain is exempt: white on its orange is the look it has always had,
      // even though dark ink would measure higher.
      const darkInk = Color(0xFF17130E);
      for (final p in kThemePalettes.where((p) => p.id != 'grain')) {
        for (final variant in [p.light, p.dark]) {
          final chosen = _contrast(variant.onBrand, variant.brand);
          final alternative = variant.onBrand == Colors.white
              ? _contrast(darkInk, variant.brand)
              : _contrast(Colors.white, variant.brand);
          expect(chosen, greaterThanOrEqualTo(alternative), reason: p.id);
        }
      }
    });
  });

  group('accent', () {
    test('is the light-mode brand, for a preview with no theme to read', () {
      for (final p in kThemePalettes) {
        expect(p.accent, p.light.brand);
      }
    });

    test('dark mode uses a lighter accent than light mode', () {
      // A near-black accent like Slate would vanish on a dark canvas.
      for (final p in kThemePalettes.where((p) => p.id != 'grain')) {
        expect(_luminance(p.dark.brand), greaterThan(_luminance(p.light.brand)),
            reason: p.id);
      }
    });
  });
}
