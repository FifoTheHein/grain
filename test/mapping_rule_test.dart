import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/ado_work_item.dart';
import 'package:harvest/models/mapping_rule.dart';

MappingRule rule(
  String name,
  List<MappingCondition> conditions, {
  int priority = 0,
  bool enabled = true,
  int projectId = 1,
  int taskId = 2,
  String? noteTemplate,
}) =>
    MappingRule(
      id: name,
      name: name,
      priority: priority,
      enabled: enabled,
      conditions: conditions,
      projectId: projectId,
      taskId: taskId,
      noteTemplate: noteTemplate,
    );

const workItem = AdoWorkItem(
  id: '13483',
  title: 'Fix login redirect',
  state: 'Active',
  workItemType: 'Bug',
  project: 'Contoso',
  areaPath: r'Contoso\Web\API',
  iterationPath: r'Contoso\Sprint 42',
  assignedToName: 'Sam Rivers',
  tags: ['hotfix', 'customer-reported'],
);

void main() {
  group('operators', () {
    final ctx = workItem.matchContext;

    test('equals is case-insensitive and trims', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.workItemType,
              operator: ConditionOperator.equals,
              value: '  bug ',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
    });

    test('contains matches a substring of the title', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.title,
              operator: ConditionOperator.contains,
              value: 'LOGIN',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
    });

    test('startsWith anchors at the front', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.title,
              operator: ConditionOperator.startsWith,
              value: 'Fix',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.title,
              operator: ConditionOperator.startsWith,
              value: 'login',
            )
          ]),
          ctx,
        ),
        isFalse,
      );
    });

    test('inList splits on commas', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.state,
              operator: ConditionOperator.inList,
              value: 'new, active, resolved',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
    });

    test('underPath matches a prefix of path segments, not raw text', () {
      MappingCondition under(String value) => MappingCondition(
            field: WorkItemField.areaPath,
            operator: ConditionOperator.underPath,
            value: value,
          );
      expect(ruleMatches(rule('r', [under(r'Contoso\Web')]), ctx), isTrue);
      expect(ruleMatches(rule('r', [under('Contoso/Web')]), ctx), isTrue,
          reason: 'either separator is accepted');
      expect(ruleMatches(rule('r', [under(r'Contoso\Web\API\Auth')]), ctx),
          isFalse,
          reason: 'target deeper than the field cannot match');
      expect(ruleMatches(rule('r', [under('Cont')]), ctx), isFalse,
          reason: 'segments match whole, not by prefix text');
    });

    test('regex is case-insensitive; a malformed pattern never matches', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.title,
              operator: ConditionOperator.regex,
              value: r'^fix .*redirect$',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.title,
              operator: ConditionOperator.regex,
              value: '[unclosed',
            )
          ]),
          ctx,
        ),
        isFalse,
      );
    });

    test('list fields match when any element matches', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.tags,
              operator: ConditionOperator.equals,
              value: 'hotfix',
            )
          ]),
          ctx,
        ),
        isTrue,
      );
    });

    test('negate inverts a single condition', () {
      expect(
        ruleMatches(
          rule('r', const [
            MappingCondition(
              field: WorkItemField.state,
              operator: ConditionOperator.equals,
              value: 'Closed',
              negate: true,
            )
          ]),
          ctx,
        ),
        isTrue,
      );
    });

    test('a missing field never matches, but negate flips that', () {
      const noArea = AdoWorkItem(id: '1', title: 't', state: 'Active');
      const condition = MappingCondition(
        field: WorkItemField.areaPath,
        operator: ConditionOperator.contains,
        value: 'Web',
      );
      expect(ruleMatches(rule('r', const [condition]), noArea.matchContext),
          isFalse);
      expect(
        ruleMatches(
          rule('r', [condition.copyWith(negate: true)]),
          noArea.matchContext,
        ),
        isTrue,
      );
    });
  });

  group('resolveMapping', () {
    test('conditions are ANDed — one failure loses the rule', () {
      final r = rule('r', const [
        MappingCondition(
          field: WorkItemField.workItemType,
          operator: ConditionOperator.equals,
          value: 'Bug',
        ),
        MappingCondition(
          field: WorkItemField.state,
          operator: ConditionOperator.equals,
          value: 'Closed',
        ),
      ]);
      expect(resolveMapping([r], workItem.matchContext), isNull);
    });

    test('an empty condition list matches everything', () {
      final match = resolveMapping([rule('catch-all', const [])],
          workItem.matchContext);
      expect(match?.rule.name, 'catch-all');
    });

    test('lowest priority wins regardless of list order', () {
      final specific = rule(
        'specific',
        const [
          MappingCondition(
            field: WorkItemField.tags,
            operator: ConditionOperator.equals,
            value: 'hotfix',
          )
        ],
        priority: 1,
        projectId: 10,
      );
      final catchAll = rule('catch-all', const [], priority: 5, projectId: 99);
      final match = resolveMapping([catchAll, specific], workItem.matchContext);
      expect(match?.rule.name, 'specific');
      expect(match?.projectId, 10);
    });

    test('disabled rules are skipped', () {
      final disabled = rule('off', const [], priority: 0, enabled: false);
      final on = rule('on', const [], priority: 1);
      expect(
        resolveMapping([disabled, on], workItem.matchContext)?.rule.name,
        'on',
      );
    });

    test('no match returns null', () {
      final r = rule('r', const [
        MappingCondition(
          field: WorkItemField.project,
          operator: ConditionOperator.equals,
          value: 'Fabrikam',
        )
      ]);
      expect(resolveMapping([r], workItem.matchContext), isNull);
    });
  });

  group('note templates', () {
    test('expands known placeholders, joining list values', () {
      expect(
        renderNoteTemplate(
            'Working {type} {id} ({state}) in {areaPath} — {title}',
            workItem.matchContext),
        r'Working Bug 13483 (Active) in Contoso\Web\API — Fix login redirect',
      );
    });

    test('leaves unknown or unset placeholders untouched', () {
      const bare = AdoWorkItem(id: '7', title: 'T', state: 'New');
      expect(
        renderNoteTemplate('{id} {nope} {areaPath}', bare.matchContext),
        '7 {nope} {areaPath}',
      );
    });
  });

  group('AdoWorkItem', () {
    test('parses ADO field payloads including semicolon tags', () {
      final item = AdoWorkItem.fromJson('42', const {
        'fields': {
          'System.Title': 'Add caching',
          'System.State': 'New',
          'System.WorkItemType': 'User Story',
          'System.TeamProject': 'Contoso',
          'System.AreaPath': r'Contoso\Platform',
          'System.IterationPath': r'Contoso\Sprint 1',
          'System.AssignedTo': {'displayName': 'Alex Chen'},
          'System.Tags': 'perf; backend ;',
        }
      });
      expect(item.project, 'Contoso');
      expect(item.assignedToName, 'Alex Chen');
      expect(item.tags, ['perf', 'backend']);
    });

    test('tolerates a payload with only the original fields', () {
      final item = AdoWorkItem.fromJson('42', const {
        'fields': {'System.Title': 'Legacy', 'System.State': 'Active'}
      });
      expect(item.tags, isEmpty);
      expect(item.areaPath, isNull);
      expect(item.matchContext[WorkItemField.title], 'Legacy');
    });
  });

  group('json round-trip', () {
    test('preserves conditions, negate and note template', () {
      final original = rule(
        'Platform bugs',
        const [
          MappingCondition(
            field: WorkItemField.areaPath,
            operator: ConditionOperator.underPath,
            value: r'Contoso\Platform',
          ),
          MappingCondition(
            field: WorkItemField.state,
            operator: ConditionOperator.equals,
            value: 'Closed',
            negate: true,
          ),
        ],
        priority: 3,
        noteTemplate: '{type} {id}',
      );
      final restored = MappingRule.fromJson(original.toJson());
      expect(restored.name, original.name);
      expect(restored.priority, 3);
      expect(restored.noteTemplate, '{type} {id}');
      expect(restored.conditions.length, 2);
      expect(restored.conditions[1].negate, isTrue);
      expect(restored.conditions[0].operator, ConditionOperator.underPath);
    });
  });
}
