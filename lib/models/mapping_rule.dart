/// Work item → Harvest project/task mapping rules.
///
/// A [MappingRule] describes when an ADO work item should select a particular
/// Harvest project/task. Rules are evaluated in ascending [MappingRule.priority]
/// order and the first fully-matching enabled rule wins. Everything in this
/// file is pure — no I/O, no Flutter — so it can be unit tested directly.
library;

/// How a single condition compares its field against its value.
enum ConditionOperator {
  /// Exact match, case-insensitive.
  equals,

  /// Substring match, case-insensitive.
  contains,

  /// Prefix match, case-insensitive.
  startsWith,

  /// Dart regular expression, case-insensitive. A malformed pattern never
  /// matches — validation surfaces the error in the editor instead.
  regex,

  /// Field is one of a comma-separated list, case-insensitive and trimmed.
  inList,

  /// Field is at or below a `\` / `/` delimited path. Built for ADO area and
  /// iteration paths, where `Contoso\Web` should also match `Contoso\Web\API`.
  underPath,
}

extension ConditionOperatorLabel on ConditionOperator {
  String get label => switch (this) {
        ConditionOperator.equals => 'equals',
        ConditionOperator.contains => 'contains',
        ConditionOperator.startsWith => 'starts with',
        ConditionOperator.regex => 'matches regex',
        ConditionOperator.inList => 'is one of',
        ConditionOperator.underPath => 'is under path',
      };

  String get wireName => name;

  static ConditionOperator fromWireName(String? name) =>
      ConditionOperator.values.firstWhere(
        (o) => o.name == name,
        orElse: () => ConditionOperator.equals,
      );
}

/// Canonical work item field names usable in a condition. These are the keys of
/// the [MatchContext] built by `AdoWorkItem.matchContext`.
abstract final class WorkItemField {
  static const project = 'project';
  static const iterationPath = 'iterationPath';
  static const areaPath = 'areaPath';
  static const workItemType = 'workItemType';
  static const state = 'state';
  static const tags = 'tags';
  static const title = 'title';
  static const assignedTo = 'assignedTo';
  static const id = 'id';

  static const all = [
    project,
    iterationPath,
    areaPath,
    workItemType,
    state,
    tags,
    title,
    assignedTo,
    id,
  ];

  static String labelFor(String field) => switch (field) {
        project => 'Project',
        iterationPath => 'Iteration path',
        areaPath => 'Area path',
        workItemType => 'Work item type',
        state => 'State',
        tags => 'Tags',
        title => 'Title',
        assignedTo => 'Assigned to',
        id => 'Work item #',
        _ => field,
      };
}

/// Field values are either a single string or a list (e.g. tags), where a list
/// matches if *any* element satisfies the operator.
typedef MatchContext = Map<String, Object?>;

class MappingCondition {
  final String field;
  final ConditionOperator operator;
  final String value;

  /// Inverts the result of this single condition.
  final bool negate;

  const MappingCondition({
    required this.field,
    required this.operator,
    required this.value,
    this.negate = false,
  });

  MappingCondition copyWith({
    String? field,
    ConditionOperator? operator,
    String? value,
    bool? negate,
  }) =>
      MappingCondition(
        field: field ?? this.field,
        operator: operator ?? this.operator,
        value: value ?? this.value,
        negate: negate ?? this.negate,
      );

  Map<String, dynamic> toJson() => {
        'field': field,
        'operator': operator.wireName,
        'value': value,
        if (negate) 'negate': true,
      };

  factory MappingCondition.fromJson(Map<String, dynamic> json) =>
      MappingCondition(
        field: json['field'] as String? ?? WorkItemField.title,
        operator:
            ConditionOperatorLabel.fromWireName(json['operator'] as String?),
        value: json['value'] as String? ?? '',
        negate: json['negate'] as bool? ?? false,
      );

  /// Human-readable summary, e.g. `Area path is under Contoso\Web`.
  String get summary {
    final not = negate ? 'not ' : '';
    return '${WorkItemField.labelFor(field)} $not${operator.label} "$value"';
  }
}

class MappingRule {
  final String id;
  final String name;

  /// Lower number = evaluated first. First fully-matching rule wins.
  final int priority;
  final bool enabled;

  /// ALL conditions must match (logical AND). An empty list matches everything.
  final List<MappingCondition> conditions;

  final int projectId;
  final int taskId;

  /// Optional note prefilled when this rule matches. Supports the placeholders
  /// documented on [renderNoteTemplate].
  final String? noteTemplate;

  const MappingRule({
    required this.id,
    required this.name,
    required this.projectId,
    required this.taskId,
    this.priority = 0,
    this.enabled = true,
    this.conditions = const [],
    this.noteTemplate,
  });

  MappingRule copyWith({
    String? name,
    int? priority,
    bool? enabled,
    List<MappingCondition>? conditions,
    int? projectId,
    int? taskId,
    String? noteTemplate,
    bool clearNoteTemplate = false,
  }) =>
      MappingRule(
        id: id,
        name: name ?? this.name,
        priority: priority ?? this.priority,
        enabled: enabled ?? this.enabled,
        conditions: conditions ?? this.conditions,
        projectId: projectId ?? this.projectId,
        taskId: taskId ?? this.taskId,
        noteTemplate:
            clearNoteTemplate ? null : (noteTemplate ?? this.noteTemplate),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'priority': priority,
        'enabled': enabled,
        'conditions': conditions.map((c) => c.toJson()).toList(),
        'projectId': projectId,
        'taskId': taskId,
        if (noteTemplate != null) 'noteTemplate': noteTemplate,
      };

  factory MappingRule.fromJson(Map<String, dynamic> json) => MappingRule(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Rule',
        priority: (json['priority'] as num?)?.toInt() ?? 0,
        enabled: json['enabled'] as bool? ?? true,
        conditions: (json['conditions'] as List<dynamic>? ?? [])
            .map((c) => MappingCondition.fromJson(c as Map<String, dynamic>))
            .toList(),
        projectId: (json['projectId'] as num).toInt(),
        taskId: (json['taskId'] as num).toInt(),
        noteTemplate: json['noteTemplate'] as String?,
      );
}

/// The rule that matched, ready to apply.
class MappingMatch {
  final MappingRule rule;
  const MappingMatch(this.rule);

  int get projectId => rule.projectId;
  int get taskId => rule.taskId;
}

String _norm(String s) => s.trim().toLowerCase();

/// Splits an ADO path on either separator, dropping empty segments.
List<String> _segments(String path) => path
    .split(RegExp(r'[\\/]'))
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .toList();

bool _matchesUnderPath(String fieldValue, String target) {
  final f = _segments(fieldValue).map(_norm).toList();
  final t = _segments(target).map(_norm).toList();
  if (t.isEmpty) return true;
  if (t.length > f.length) return false;
  for (var i = 0; i < t.length; i++) {
    if (t[i] != f[i]) return false;
  }
  return true;
}

bool _matchesScalar(
    ConditionOperator op, String fieldValue, String condValue) {
  switch (op) {
    case ConditionOperator.equals:
      return _norm(fieldValue) == _norm(condValue);
    case ConditionOperator.contains:
      return _norm(fieldValue).contains(_norm(condValue));
    case ConditionOperator.startsWith:
      return _norm(fieldValue).startsWith(_norm(condValue));
    case ConditionOperator.inList:
      return condValue
          .split(',')
          .map(_norm)
          .where((v) => v.isNotEmpty)
          .contains(_norm(fieldValue));
    case ConditionOperator.underPath:
      return _matchesUnderPath(fieldValue, condValue);
    case ConditionOperator.regex:
      try {
        return RegExp(condValue, caseSensitive: false).hasMatch(fieldValue);
      } catch (_) {
        // A malformed pattern never matches.
        return false;
      }
  }
}

bool _conditionMatches(MappingCondition condition, MatchContext context) {
  final raw = context[condition.field];
  final bool result;
  if (raw == null) {
    result = false;
  } else if (raw is List) {
    result = raw
        .whereType<String>()
        .any((v) => _matchesScalar(condition.operator, v, condition.value));
  } else {
    result = _matchesScalar(condition.operator, raw.toString(), condition.value);
  }
  return condition.negate ? !result : result;
}

/// True when every condition matches. An empty condition list matches anything.
bool conditionsMatch(
        List<MappingCondition> conditions, MatchContext context) =>
    conditions.every((c) => _conditionMatches(c, context));

/// True when all of [rule]'s conditions match [context].
bool ruleMatches(MappingRule rule, MatchContext context) =>
    conditionsMatch(rule.conditions, context);

/// Resolves the first enabled rule — by ascending priority, then by insertion
/// order for ties — whose conditions all match. Returns null when none do.
MappingMatch? resolveMapping(
  List<MappingRule> rules,
  MatchContext context,
) {
  final candidates = rules.where((r) => r.enabled).toList()
    ..sort((a, b) => a.priority.compareTo(b.priority));
  for (final rule in candidates) {
    if (ruleMatches(rule, context)) return MappingMatch(rule);
  }
  return null;
}

/// Expands `{id}`, `{title}`, `{type}`, `{state}`, `{project}`, `{areaPath}`,
/// `{iterationPath}` and `{assignedTo}` in a rule's note template using
/// [context]. Unknown placeholders are left untouched so a stray brace in a
/// note never silently disappears.
String renderNoteTemplate(String template, MatchContext context) {
  const aliases = {
    'id': WorkItemField.id,
    'title': WorkItemField.title,
    'type': WorkItemField.workItemType,
    'state': WorkItemField.state,
    'project': WorkItemField.project,
    'areaPath': WorkItemField.areaPath,
    'iterationPath': WorkItemField.iterationPath,
    'assignedTo': WorkItemField.assignedTo,
  };
  return template.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final field = aliases[m.group(1)];
    if (field == null) return m.group(0)!;
    final value = context[field];
    if (value == null) return m.group(0)!;
    if (value is List) return value.whereType<String>().join(', ');
    return value.toString();
  });
}
