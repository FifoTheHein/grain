import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ado_work_item.dart';
import '../models/mapping_rule.dart';

/// Stores the work item → Harvest project/task mapping rules and resolves a
/// work item against them. Rules live in localStorage like every other setting.
class MappingRuleProvider extends ChangeNotifier {
  static const _rulesKey = 'mapping_rules_v1';
  static const _enabledKey = 'mapping_rules_enabled';

  final List<MappingRule> _rules = [];
  bool _autoApply = true;

  /// Rules in evaluation order (ascending priority).
  List<MappingRule> get rules => List.unmodifiable(_rules);

  /// When false, rules are kept but never applied automatically.
  bool get autoApply => _autoApply;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_rulesKey);
    _rules.clear();
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        _rules.addAll(list.map(
            (r) => MappingRule.fromJson(r as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt payload — start empty rather than blocking the app.
      }
    }
    _sort();
    _autoApply = prefs.getBool(_enabledKey) ?? true;
    notifyListeners();
  }

  /// Resolves [item] against the enabled rules. Returns null when [autoApply]
  /// is off or nothing matches.
  MappingMatch? match(AdoWorkItem item) {
    if (!_autoApply) return null;
    return resolveMapping(_rules, item.matchContext);
  }

  /// Resolves regardless of [autoApply] — used by the settings preview so a
  /// rule can be tested while auto-apply is switched off.
  MappingMatch? matchIgnoringToggle(AdoWorkItem item) =>
      resolveMapping(_rules, item.matchContext);

  Future<void> setAutoApply(bool value) async {
    _autoApply = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Inserts a new rule at the end of the evaluation order, or replaces the
  /// existing rule with the same id.
  Future<void> upsert(MappingRule rule) async {
    final index = _rules.indexWhere((r) => r.id == rule.id);
    if (index >= 0) {
      _rules[index] = rule;
    } else {
      _rules.add(rule.copyWith(priority: _nextPriority()));
    }
    _sort();
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String id) async {
    _rules.removeWhere((r) => r.id == id);
    _renumber();
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    final index = _rules.indexWhere((r) => r.id == id);
    if (index < 0) return;
    _rules[index] = _rules[index].copyWith(enabled: enabled);
    notifyListeners();
    await _persist();
  }

  /// Moves the rule at [oldIndex] to [newIndex] and rewrites priorities to
  /// match the new visual order.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _rules.length) return;
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    target = target.clamp(0, _rules.length - 1);
    final rule = _rules.removeAt(oldIndex);
    _rules.insert(target, rule);
    _renumber();
    notifyListeners();
    await _persist();
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  int _nextPriority() =>
      _rules.isEmpty ? 0 : _rules.map((r) => r.priority).reduce((a, b) => a > b ? a : b) + 1;

  void _sort() => _rules.sort((a, b) => a.priority.compareTo(b.priority));

  /// Reassigns priorities to 0..n-1 in current list order.
  void _renumber() {
    for (var i = 0; i < _rules.length; i++) {
      _rules[i] = _rules[i].copyWith(priority: i);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _rulesKey, jsonEncode(_rules.map((r) => r.toJson()).toList()));
  }
}
