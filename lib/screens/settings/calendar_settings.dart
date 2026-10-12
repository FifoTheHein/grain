import 'package:flutter/material.dart';
import '../../widgets/calendar_import_settings.dart';
import '../../widgets/mapping_rule_editor.dart';
import 'settings_shared.dart';

/// The calendar import and the meeting rules that place what it imports.
class CalendarSettingsPage extends StatelessWidget {
  const CalendarSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPageBody(children: [
      const SettingsSectionHeader(title: 'Calendar Import'),
      const SizedBox(height: 8),
      const CalendarImportSettings(),
      const SettingsSectionDivider(),
      SettingsSectionHeader(
        title: 'Meeting Rules',
        action: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Add'),
          onPressed: () =>
              showMappingRuleDialog(context, kind: RuleKind.meeting),
        ),
      ),
      const SettingsHint(
          'Pick the project for an imported calendar meeting. First match '
          'wins; then a work item number in the title (#123) is tried '
          'through the work item rules, then the Calendar Import default.'),
      MappingRuleList(kind: RuleKind.meeting),
    ]);
  }
}
