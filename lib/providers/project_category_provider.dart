import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_category.dart';

class ProjectCategoryProvider extends ChangeNotifier {
  static const _categoriesKey = 'project_categories_v1';
  static const _weeklyGoalKey = 'weekly_goal_hours';
  static const _workDayStartKey = 'work_day_start';
  static const _workDayEndKey = 'work_day_end';
  static const _breakHoursKey = 'break_hours';

  final Map<int, ProjectCategory> _categories = {};
  double _weeklyGoalHours = 40.0;
  TimeOfDay _workDayStart = const TimeOfDay(hour: 8, minute: 30);
  TimeOfDay _workDayEnd = const TimeOfDay(hour: 17, minute: 0);
  double _breakHours = 0.5;

  // 12-color fixed palette (Material 500-level, warm-to-cool spread)
  static const _palette = [
    _Swatch(Color(0xFFFA5D24), Color(0xFFFEE6DA)), // brand orange
    _Swatch(Color(0xFF7C5CFF), Color(0xFFEEE9FF)), // violet
    _Swatch(Color(0xFF14B8A6), Color(0xFFD7F5F0)), // teal
    _Swatch(Color(0xFF8A837A), Color(0xFFF1ECE3)), // warm gray
    _Swatch(Color(0xFF2563EB), Color(0xFFDCEAFD)), // blue
    _Swatch(Color(0xFF16A34A), Color(0xFFDCFCE7)), // green
    _Swatch(Color(0xFFC026D3), Color(0xFFF5D0FE)), // purple
    _Swatch(Color(0xFFD97706), Color(0xFFFEF3C7)), // amber
    _Swatch(Color(0xFFDC2626), Color(0xFFFEE2E2)), // red
    _Swatch(Color(0xFF0891B2), Color(0xFFCFFAFE)), // cyan
    _Swatch(Color(0xFF65A30D), Color(0xFFECFCCB)), // lime
    _Swatch(Color(0xFFDB2777), Color(0xFFFCE7F3)), // pink
  ];

  Map<int, ProjectCategory> get categories => Map.unmodifiable(_categories);
  double get weeklyGoalHours => _weeklyGoalHours;
  TimeOfDay get workDayStart => _workDayStart;
  TimeOfDay get workDayEnd => _workDayEnd;
  double get breakHours => _breakHours;

  double get dailyGoalHours {
    final startMinutes = _workDayStart.hour * 60 + _workDayStart.minute;
    final endMinutes = _workDayEnd.hour * 60 + _workDayEnd.minute;
    return ((endMinutes - startMinutes) / 60.0) - _breakHours;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_categoriesKey);
    if (raw != null) {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _categories.clear();
      map.forEach((k, v) {
        _categories[int.parse(k)] =
            ProjectCategory.fromJson(v as Map<String, dynamic>);
      });
    }
    _weeklyGoalHours = prefs.getDouble(_weeklyGoalKey) ?? 40.0;
    _workDayStart = _parseTime(prefs.getString(_workDayStartKey), const TimeOfDay(hour: 8, minute: 30));
    _workDayEnd = _parseTime(prefs.getString(_workDayEndKey), const TimeOfDay(hour: 17, minute: 0));
    _breakHours = prefs.getDouble(_breakHoursKey) ?? 0.5;
    notifyListeners();
  }

  /// Returns the stored category for [projectId], or auto-assigns one from
  /// the palette using the project ID as a deterministic index.
  ProjectCategory categoryFor(int projectId, {required String fallbackCode}) {
    if (_categories.containsKey(projectId)) return _categories[projectId]!;
    final swatch = _palette[projectId.abs() % _palette.length];
    return ProjectCategory(
      color: swatch.color,
      tint: swatch.tint,
      code: fallbackCode.isEmpty ? '?' : fallbackCode,
    );
  }

  Future<void> setCategory(int projectId, ProjectCategory cat) async {
    _categories[projectId] = cat;
    notifyListeners();
    await _persist();
  }

  Future<void> setWeeklyGoal(double hours) async {
    _weeklyGoalHours = hours.clamp(1.0, 168.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_weeklyGoalKey, _weeklyGoalHours);
  }

  Future<void> setWorkDayStart(TimeOfDay time) async {
    _workDayStart = time;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workDayStartKey, _formatTime(time));
  }

  Future<void> setWorkDayEnd(TimeOfDay time) async {
    _workDayEnd = time;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_workDayEndKey, _formatTime(time));
  }

  Future<void> setBreakHours(double hours) async {
    _breakHours = hours.clamp(0.0, 24.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_breakHoursKey, _breakHours);
  }

  static String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTime(String? s, TimeOfDay fallback) {
    if (s == null) return fallback;
    final parts = s.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = {
      for (final e in _categories.entries) '${e.key}': e.value.toJson(),
    };
    await prefs.setString(_categoriesKey, jsonEncode(map));
  }
}

class _Swatch {
  final Color color;
  final Color tint;
  const _Swatch(this.color, this.tint);
}
