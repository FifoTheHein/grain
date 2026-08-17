# Theming

Two independent choices: **mode** (System / Light / Dark, `ThemeModeProvider`)
and **palette** (`ThemePaletteProvider`). Every palette ships both a light and
a dark variant, so the two never conflict.

**Palettes (`lib/theme/theme_palettes.dart`)** — `GrainThemePalette { id,
label, description, light, dark }`, unit tested in
`test/theme_palette_test.dart`.

- `kThemePalettes` is the catalogue in picker order; the first entry is the
  default. `themePaletteById` falls back to it, so a stored id outlives the
  palette it named.
- `id` is a persisted key (`theme_palette_v1`). Never rename or reuse one.
- **Grain** is spelled out by hand — its warm-paper light mode and cool-gray
  dark mode were tuned, not computed. The rest come from `_derive`, which mixes
  the surface steps, strokes and ink ramp out of the background and ink, so a
  new palette needs a handful of colours rather than twenty-six.
- `_derive` takes a separate `accentOnDark`, because a light-mode accent chosen
  for white (Modern Slate's near-black, say) disappears on a dark canvas.

**The accent lives in the palette, not in tokens.** `HarvestPalette` carries
`brand` and `brand600` alongside the surfaces, reached with
`HarvestTokens.of(context)`. `HarvestTokens` keeps only what is genuinely
constant across palettes: the ADO work-item state colours, the semantic
error/warn/success trio, and the layout breakpoint. Anything accent-coloured
must read the palette, which is why a few widgets lost a `const` on a
`TextStyle`.

**Contrast is tested, not assumed.** `test/theme_palette_test.dart` asserts
body text clears 7:1 against its canvas, secondary ink 4.5:1, tertiary 3:1,
that the accent reads against its own tint, and that the ink ramp weakens
monotonically. The first run caught Modern Slate's tertiary ink at 2.91:1 and
the derivation was tightened. Add a palette and these run against it
automatically.

**Settings** — the Appearance section holds the mode toggle and
`_ThemePaletteSelector`, whose cards preview each palette in the mode you are
currently in, so what you see is what tapping it gives you.
