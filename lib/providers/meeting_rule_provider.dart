import 'mapping_rule_provider.dart';

/// Meeting → Harvest project/task rules for the calendar import. The same
/// engine, editor and storage shape as the work item rules, matched against
/// `meetingMatchContext` instead, and kept under their own keys. A separate
/// type so both can sit in the provider tree.
class MeetingRuleProvider extends MappingRuleProvider {
  MeetingRuleProvider()
      : super(
          rulesKey: 'meeting_rules_v1',
          enabledKey: 'meeting_rules_enabled',
        );
}
