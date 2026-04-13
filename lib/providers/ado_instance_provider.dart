import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/time_entry.dart';

class AdoInstanceProvider extends ChangeNotifier {
  List<AdoInstance> instances = [];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('ado_instances');
    if (stored != null) {
      final list = jsonDecode(stored) as List<dynamic>;
      instances = list
          .map((e) => AdoInstance.fromJson(e as Map<String, dynamic>))
          .toList();
    } else {
      instances = List.of(AppConfig.defaultAdoInstances);
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'ado_instances',
      jsonEncode(instances.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> add(AdoInstance instance) async {
    instances = [...instances, instance];
    await _save();
    notifyListeners();
  }

  Future<void> update(int index, AdoInstance instance) async {
    instances = [...instances]..[index] = instance;
    await _save();
    notifyListeners();
  }

  Future<void> remove(int index) async {
    instances = [...instances]..removeAt(index);
    await _save();
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    instances = List.of(AppConfig.defaultAdoInstances);
    await _save();
    notifyListeners();
  }
}
