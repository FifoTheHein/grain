import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/quick_template.dart';

QuickTemplate template({
  String id = 't1',
  String label = 'PR Reviews',
  int projectId = 1,
  int taskId = 2,
  String? notes,
  int iconIndex = 0,
  int colorIndex = 0,
  int sortOrder = 0,
  bool enabled = true,
}) =>
    QuickTemplate(
      id: id,
      label: label,
      projectId: projectId,
      taskId: taskId,
      notes: notes,
      iconIndex: iconIndex,
      colorIndex: colorIndex,
      sortOrder: sortOrder,
      enabled: enabled,
    );

void main() {
  group('json round-trip', () {
    test('preserves every field', () {
      final original = template(
        notes: 'Reviewing pull requests',
        iconIndex: 3,
        colorIndex: 5,
        sortOrder: 2,
        enabled: false,
      );
      final restored = QuickTemplate.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.label, 'PR Reviews');
      expect(restored.projectId, 1);
      expect(restored.taskId, 2);
      expect(restored.notes, 'Reviewing pull requests');
      expect(restored.iconIndex, 3);
      expect(restored.colorIndex, 5);
      expect(restored.sortOrder, 2);
      expect(restored.enabled, isFalse);
    });

    test('omits null notes and restores them as null', () {
      final json = template().toJson();
      expect(json.containsKey('notes'), isFalse);
      expect(QuickTemplate.fromJson(json).notes, isNull);
    });

    test('tolerates a payload missing the optional fields', () {
      final restored = QuickTemplate.fromJson(const {
        'id': 'x',
        'label': 'Standup',
        'projectId': 4,
        'taskId': 5,
      });
      expect(restored.iconIndex, 0);
      expect(restored.colorIndex, 0);
      expect(restored.sortOrder, 0);
      expect(restored.enabled, isTrue);
    });
  });

  group('copyWith', () {
    test('keeps the id and changes only what is passed', () {
      final updated = template(notes: 'old').copyWith(label: 'Standup');
      expect(updated.id, 't1');
      expect(updated.label, 'Standup');
      expect(updated.notes, 'old');
    });

    test('clearNotes wins over a passed value', () {
      final updated =
          template(notes: 'old').copyWith(notes: 'new', clearNotes: true);
      expect(updated.notes, isNull);
    });
  });

  group('icon and colour lookup', () {
    test('resolves by index', () {
      expect(template(iconIndex: 2).icon, kTemplateIcons[2]);
      expect(template(colorIndex: 4).color, kTemplateColors[4]);
    });

    test('clamps an out-of-range index instead of throwing', () {
      // A stored template can outlive a change to the palette length.
      expect(template(iconIndex: 99).icon, kTemplateIcons.last);
      expect(template(colorIndex: -1).color, kTemplateColors.first);
    });
  });
}
