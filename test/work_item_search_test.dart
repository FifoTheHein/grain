import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/ado_work_item.dart';
import 'package:harvest/models/work_item_search.dart';

AdoWorkItem item(
  String id, {
  String title = 'Untitled',
  String state = 'Active',
  String? type = 'Task',
  String? project = 'Contoso',
  List<String> tags = const [],
  String? parentId,
}) =>
    AdoWorkItem(
      id: id,
      title: title,
      state: state,
      workItemType: type,
      project: project,
      tags: tags,
      parentId: parentId,
    );

List<String> idsOf(List<AdoWorkItem> items) => items.map((i) => i.id).toList();

void main() {
  group('matchesWorkItem', () {
    final subject = item(
      '13483',
      title: 'Fix login redirect',
      state: 'Active',
      type: 'Bug',
      project: 'Contoso',
      tags: ['hotfix', 'customer-reported'],
    );

    test('an empty query matches everything', () {
      expect(matchesWorkItem(subject, ''), isTrue);
      expect(matchesWorkItem(subject, '   '), isTrue);
    });

    test('matches on id, with or without a leading hash', () {
      expect(matchesWorkItem(subject, '13483'), isTrue);
      expect(matchesWorkItem(subject, '#13483'), isTrue);
    });

    test('a partial id matches as a substring', () {
      expect(matchesWorkItem(subject, '483'), isTrue);
      expect(matchesWorkItem(subject, '#348'), isTrue);
    });

    test('matches title, type, state, project and tags case-insensitively', () {
      expect(matchesWorkItem(subject, 'LOGIN'), isTrue);
      expect(matchesWorkItem(subject, 'bug'), isTrue);
      expect(matchesWorkItem(subject, 'active'), isTrue);
      expect(matchesWorkItem(subject, 'contoso'), isTrue);
      expect(matchesWorkItem(subject, 'HOTFIX'), isTrue);
    });

    test('does not match an unrelated query', () {
      expect(matchesWorkItem(subject, 'deployment'), isFalse);
    });

    test('tolerates missing type and project', () {
      final bare = item('7', title: 'Bare', type: null, project: null);
      expect(matchesWorkItem(bare, 'bare'), isTrue);
      expect(matchesWorkItem(bare, 'task'), isFalse);
    });
  });

  group('filterWorkItems', () {
    test('keeps incoming order', () {
      final items = [
        item('3', title: 'alpha'),
        item('1', title: 'alpha too'),
        item('2', title: 'beta'),
      ];
      expect(idsOf(filterWorkItems(items, 'alpha')), ['3', '1']);
    });
  });

  group('buildWorkItemTree', () {
    test('nests children under parents, keeping sibling order', () {
      final tree = buildWorkItemTree([
        item('1', type: 'User Story'),
        item('2', parentId: '1'),
        item('3', parentId: '1'),
      ]);
      expect(tree.length, 1);
      expect(tree.single.item.id, '1');
      expect(idsOf(tree.single.children.map((c) => c.item).toList()),
          ['2', '3']);
    });

    test('an item whose parent was not fetched is a root', () {
      final tree = buildWorkItemTree([item('2', parentId: '999')]);
      expect(tree.length, 1);
      expect(tree.single.item.id, '2');
      expect(tree.single.children, isEmpty);
    });

    test('nests more than one level deep', () {
      final tree = buildWorkItemTree([
        item('1'),
        item('2', parentId: '1'),
        item('3', parentId: '2'),
      ]);
      expect(flattenWithDepth(tree).map((r) => r.depth), [0, 1, 2]);
    });

    test('a duplicate id collapses onto its first occurrence', () {
      final tree = buildWorkItemTree([
        item('1', title: 'first'),
        item('1', title: 'second'),
      ]);
      expect(tree.length, 1);
      expect(tree.single.item.title, 'first');
    });

    test('an item parented to itself is a root, not a loop', () {
      final tree = buildWorkItemTree([item('1', parentId: '1')]);
      expect(tree.length, 1);
      expect(tree.single.children, isEmpty);
    });

    test('a parent cycle degrades to roots instead of hanging', () {
      final tree = buildWorkItemTree([
        item('1', parentId: '2'),
        item('2', parentId: '1'),
      ]);
      expect(idsOf(flattenTree(tree)).toSet(), {'1', '2'});
      expect(tree.length, 2, reason: 'both fall back to roots');
    });

    test('an empty list yields an empty forest', () {
      expect(buildWorkItemTree([]), isEmpty);
    });
  });

  group('filterWorkItemTree', () {
    List<WorkItemNode> tree() => buildWorkItemTree([
          item('1', title: 'Checkout epic', type: 'User Story'),
          item('2', title: 'Fix login redirect', parentId: '1'),
          item('3', title: 'Update copy', parentId: '1'),
          item('4', title: 'Unrelated story', type: 'User Story'),
        ]);

    test('an empty query is a no-op', () {
      expect(flattenTree(filterWorkItemTree(tree(), '')).length, 4);
    });

    test('a matched child keeps its parent as context', () {
      final filtered = filterWorkItemTree(tree(), 'login');
      expect(filtered.length, 1);
      expect(filtered.single.item.id, '1',
          reason: 'the story is kept so the task reads under it');
      expect(idsOf(filtered.single.children.map((c) => c.item).toList()),
          ['2']);
    });

    test('a matching parent keeps only its matching children', () {
      final filtered = filterWorkItemTree(tree(), 'checkout');
      expect(filtered.single.item.id, '1');
      expect(filtered.single.children, isEmpty);
    });

    test('non-matching branches are dropped entirely', () {
      final filtered = filterWorkItemTree(tree(), 'login');
      expect(idsOf(flattenTree(filtered)), ['1', '2']);
    });

    test('no matches yields an empty forest', () {
      expect(filterWorkItemTree(tree(), 'nothing here'), isEmpty);
    });
  });

  group('flattening', () {
    test('flattenTree is depth-first, parents before descendants', () {
      final tree = buildWorkItemTree([
        item('1'),
        item('2', parentId: '1'),
        item('3', parentId: '2'),
        item('4'),
      ]);
      expect(idsOf(flattenTree(tree)), ['1', '2', '3', '4']);
    });

    test('flattenWithDepth reports the nesting level', () {
      final tree = buildWorkItemTree([
        item('1'),
        item('2', parentId: '1'),
        item('4'),
      ]);
      expect(flattenWithDepth(tree).map((r) => '${r.item.id}@${r.depth}'),
          ['1@0', '2@1', '4@0']);
    });
  });

  group('state filtering', () {
    List<AdoWorkItem> sample() => [
          item('1', state: 'In Progress'),
          item('2', state: 'Ready for Development'),
          item('3', state: 'In Progress'),
          item('4', state: 'Awaiting PR'),
          item('5', state: 'Blocked'),
        ];

    test('stateCounts buckets by state as ADO spelled it', () {
      expect(stateCounts(sample()), {
        'In Progress': 2,
        'Ready for Development': 1,
        'Awaiting PR': 1,
        'Blocked': 1,
      });
    });

    test('availableStates is alphabetical, so chips do not jump on refresh',
        () {
      expect(availableStates(sample()),
          ['Awaiting PR', 'In Progress', 'Ready for Development']);
    });

    test('availableStates omits Blocked', () {
      expect(availableStates(sample()), isNot(contains('Blocked')));
    });

    test('filterByState narrows to one state, case-insensitively', () {
      expect(idsOf(filterByState(sample(), 'in progress')), ['1', '3']);
    });

    test('a null or blank state means all statuses', () {
      expect(filterByState(sample(), null).length, 5);
      expect(filterByState(sample(), '   ').length, 5);
    });

    test('Blocked items are still reachable without a chip', () {
      expect(idsOf(filterByState(sample(), 'Blocked')), ['5']);
      expect(idsOf(filterByState(sample(), null)), contains('5'));
    });

    test('an unknown state matches nothing', () {
      expect(filterByState(sample(), 'On Hold'), isEmpty);
    });
  });

  group('excludeCompleted', () {
    test('drops finished work whatever its casing', () {
      final items = [
        item('1', state: 'In Progress'),
        item('2', state: 'Done'),
        item('3', state: 'closed'),
        item('4', state: 'Removed'),
        item('5', state: 'Completed'),
      ];
      expect(idsOf(excludeCompleted(items)), ['1']);
    });

    test('keeps everything still in flight', () {
      final items = [
        item('1', state: 'Ready for Development'),
        item('2', state: 'Awaiting PR'),
        item('3', state: 'Blocked'),
      ];
      expect(idsOf(excludeCompleted(items)), ['1', '2', '3']);
    });

    test('finished states never become filter chips', () {
      final items = [item('1', state: 'In Progress'), item('2', state: 'Done')];
      expect(availableStates(excludeCompleted(items)), ['In Progress']);
    });
  });

  group('AdoWorkItem.parentId', () {
    test('is read from System.Parent as a string', () {
      final parsed = AdoWorkItem.fromJson('42', const {
        'fields': {
          'System.Title': 'Child',
          'System.State': 'Active',
          'System.Parent': 41,
        }
      });
      expect(parsed.parentId, '41');
    });

    test('is null when the field is absent', () {
      final parsed = AdoWorkItem.fromJson('42', const {
        'fields': {'System.Title': 'Orphan', 'System.State': 'Active'}
      });
      expect(parsed.parentId, isNull);
    });
  });
}
