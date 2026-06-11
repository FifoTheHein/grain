import 'package:flutter/material.dart';

import 'harvest_palette.dart';

class HarvestTokens {
  HarvestTokens._();

  // Brand — stable across themes
  static const brand = Color(0xFFFA5D24);
  static const brand600 = Color(0xFFE54714);

  // ADO work-item state colors — stable across themes
  static const stateActive = Color(0xFF2563EB);
  static const stateDone = Color(0xFF16A34A);
  static const stateRemoved = Color(0xFF8A837A);
  static const stateNew = Color(0xFFC026D3);

  // Semantic — stable across themes
  static const error = Color(0xFFDC2626);
  static const warn = Color(0xFFD97706);
  static const success = Color(0xFF16A34A);

  // Layout
  static const double kWideBreakpoint = 720.0;

  // Theme-aware surfaces & ink — read at runtime
  static HarvestPalette of(BuildContext context) =>
      Theme.of(context).extension<HarvestPalette>() ?? HarvestPalette.light;
}
