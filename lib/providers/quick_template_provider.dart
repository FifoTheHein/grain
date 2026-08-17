import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quick_template.dart';

/// Stores the quick templates shown as a chip row on Log Time.
class QuickTemplateProvider extends ChangeNotifier {
  static const _templatesKey = 'quick_templates_v1';

  final List<QuickTemplate> _templates = [];

  /// All templates in display order, enabled or not.
  List<QuickTemplate> get templates => List.unmodifiable(_templates);

  /// The templates the chip row actually shows.
  List<QuickTemplate> get enabledTemplates =>
      List.unmodifiable(_templates.where((t) => t.enabled));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_templatesKey);
    _templates.clear();
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _templates.addAll(
            list.map((t) => QuickTemplate.fromJson(t as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt payload — start empty rather than blocking the app.
      }
    }
    _sort();
    notifyListeners();
  }

  /// Adds a new template at the end, or replaces one with the same id.
  Future<void> upsert(QuickTemplate template) async {
    final index = _templates.indexWhere((t) => t.id == template.id);
    if (index >= 0) {
      _templates[index] = template;
    } else {
      _templates.add(template.copyWith(sortOrder: _nextSortOrder()));
    }
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    _templates.removeWhere((t) => t.id == id);
    _renumber();
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _templates.indexWhere((t) => t.id == id);
    if (index < 0) return;
    _templates[index] = _templates[index].copyWith(enabled: enabled);
    notifyListeners();
    await _persist();
  }

  /// Moves the template at [oldIndex] to [newIndex], rewriting sort orders to
  /// match the new visual order.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _templates.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, _templates.length - 1);
    final template = _templates.removeAt(oldIndex);
    _templates.insert(target, template);
    _renumber();
    notifyListeners();
    await _persist();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  int _nextSortOrder() => _templates.isEmpty
      ? 0
      : _templates.map((t) => t.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

  void _sort() => _templates.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  void _renumber() {
    for (var i = 0; i < _templates.length; i++) {
      _templates[i] = _templates[i].copyWith(sortOrder: i);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _templatesKey, jsonEncode(_templates.map((t) => t.toJson()).toList()));
  }
}
