import 'package:flutter_test/flutter_test.dart';
import 'package:harvest/models/ado_work_item.dart';
import 'package:harvest/models/calendar_event.dart';
import 'package:harvest/models/mapping_rule.dart';
import 'package:harvest/models/meeting.dart';

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

final meeting = CalendarEvent(
  uid: 'u',
  summary: 'Declined: Backlog refinement',
  start: DateTime.utc(2026, 10, 12, 8),
  end: DateTime.utc(2026, 10, 12, 9),
  location: 'Room 4 / Teams',
  description: 'Agenda: TFN support tickets',
  organizerName: 'Jane Doe',
);

bool anyText(MatchContext ctx, String value,
        {ConditionOperator op = ConditionOperator.contains,
        bool negate = false}) =>
    conditionsMatch([
      MappingCondition(
          field: kAnyTextField, operator: op, value: value, negate: negate),
    ], ctx);

void main() {
  test('both field sets offer Any text under the same key', () {
    expect(WorkItemField.anyText, kAnyTextField);
    expect(MeetingField.anyText, kAnyTextField);
    expect(WorkItemField.all, contains(kAnyTextField));
    expect(MeetingField.all, contains(kAnyTextField));
    expect(WorkItemField.labelFor(kAnyTextField), 'Any text');
    expect(MeetingField.labelFor(kAnyTextField), 'Any text');
  });

  group('work items', () {
    final ctx = workItem.matchContext;

    test('Any text searches title, tags, paths, project, type and state', () {
      expect(anyText(ctx, 'login'), isTrue); // title
      expect(anyText(ctx, 'hotfix'), isTrue); // tag
      expect(anyText(ctx, r'Web\API'), isTrue); // area path
      expect(anyText(ctx, 'Sprint 42'), isTrue); // iteration path
      expect(anyText(ctx, 'contoso'), isTrue); // project
      expect(anyText(ctx, 'bug'), isTrue); // type
      expect(anyText(ctx, 'active'), isTrue); // state
    });

    test('Any text misses text that is nowhere on the item', () {
      expect(anyText(ctx, 'refinement'), isFalse);
      expect(anyText(ctx, 'refinement', negate: true), isTrue);
    });

    test('regex works across the fields', () {
      expect(anyText(ctx, r'^customer-', op: ConditionOperator.regex), isTrue);
    });
  });

  group('meetings', () {
    final ctx = meetingMatchContext(meeting);

    test('Any text searches title, location, description and organizer', () {
      expect(anyText(ctx, 'refinement'), isTrue); // title
      expect(anyText(ctx, 'room 4'), isTrue); // location
      expect(anyText(ctx, 'tfn support'), isTrue); // description
      expect(anyText(ctx, 'jane'), isTrue); // organizer
    });

    test('the title is searched cleaned of its response prefix', () {
      expect(
          anyText(ctx, 'Backlog refinement', op: ConditionOperator.startsWith),
          isTrue);
    });

    test('Any text misses text that is nowhere on the meeting', () {
      expect(anyText(ctx, 'hotfix'), isFalse);
    });

    test('a meeting with no location or description still matches its title',
        () {
      final bare = CalendarEvent(
        uid: 'b',
        summary: 'Standup',
        start: DateTime.utc(2026, 10, 12, 8),
        end: DateTime.utc(2026, 10, 12, 8, 15),
      );
      expect(anyText(meetingMatchContext(bare), 'standup'), isTrue);
    });
  });
}
