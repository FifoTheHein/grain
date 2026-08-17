import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_palettes.dart';

/// Which colour palette the whole interface uses. Independent of light/dark,
/// which stays with [ThemeModeProvider] — every palette ships both.
class ThemePaletteProvider extends ChangeNotifier {
  static const _prefsKey = 'theme_palette_v1';

  GrainThemePalette _palette = kThemePalettes.first;
  GrainThemePalette get palette => _palette;
  String get id => _palette.id;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _palette = themePaletteById(prefs.getString(_prefsKey));
    notifyListeners();
  }

  Future<void> setPalette(String id) async {
    final next = themePaletteById(id);
    if (next.id == _palette.id) return;
    _palette = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next.id);
  }
}
