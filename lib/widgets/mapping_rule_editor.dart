import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/mapping_rule.dart';
import '../models/meeting.dart';
import '../models/project_assignment.dart';
import '../providers/assignment_provider.dart';
import '../providers/mapping_rule_provider.dart';
import '../providers/meeting_rule_provider.dart';
import '../theme/harvest_tokens.dart';

/// What a rule list edits: the field set, its wording, and which provider
/// holds the rules. Work item rules and meeting rules share every widget here.
class RuleKind {
  final List<String> fields;
  final String Function(String field) labelFor;
  final MappingCondition firstCondition;
  final MappingCondition addedCondition;
  final String autoApplyTitle;
  final String autoApplySubtitle;
  final String emptyText;
  final String matchesEverything;
  final String newRuleTitle;
  final String nameHint;
  final String noteHint;
  final String notePlaceholders;
  final MappingRuleProvider Function(BuildContext context, bool listen)
      _provider;

  const RuleKind._({
    required this.fields,
    required this.labelFor,
    required this.firstCondition,
    required this.addedCondition,
    required this.autoApplyTitle,
    required this.autoApplySubtitle,
    required this.emptyText,
    required this.matchesEverything,
    required this.newRuleTitle,
    required this.nameHint,
    required this.noteHint,
    required this.notePlaceholders,
    required MappingRuleProvider Function(BuildContext, bool) provider,
  }) : _provider = provider;

  MappingRuleProvider watch(BuildContext context) => _provider(context, true);
  MappingRuleProvider read(BuildContext context) => _provider(context, false);

  static final workItem = RuleKind._(
    fields: WorkItemField.all,
    labelFor: WorkItemField.labelFor,
    firstCondition: const MappingCondition(
      field: WorkItemField.areaPath,
      operator: ConditionOperator.underPath,
      value: '',
    ),
    addedCondition: const MappingCondition(
      field: WorkItemField.workItemType,
      operator: ConditionOperator.equals,
      value: '',
    ),
    autoApplyTitle: 'Auto-select project & task from work items',
    autoApplySubtitle: 'Applies the first matching rule when a work item loads',
    emptyText: 'No rules yet. Add one to have Grain pick the Harvest project '
        'and task for a work item automatically.',
    matchesEverything: 'Matches every work item',
    newRuleTitle: 'New work item rule',
    nameHint: 'Platform team bugs',
    noteHint: 'Investigating {type} {id}: {title}',
    notePlaceholders: 'Placeholders: {id} {title} {type} {state} {project} '
        '{areaPath} {iterationPath} {assignedTo}',
    provider: (c, listen) =>
        Provider.of<MappingRuleProvider>(c, listen: listen),
  );

  static final meeting = RuleKind._(
    fields: MeetingField.all,
    labelFor: MeetingField.labelFor,
    firstCondition: const MappingCondition(
      field: MeetingField.anyText,
      operator: ConditionOperator.contains,
      value: '',
    ),
    addedCondition: const MappingCondition(
      field: MeetingField.location,
      operator: ConditionOperator.contains,
      value: '',
    ),
    autoApplyTitle: 'Use meeting rules',
    autoApplySubtitle:
        'Off sends every meeting to the default project, or leaves it pending',
    emptyText: 'No meeting rules yet. Add one to send, say, every '
        '"Daily Scrum" to its client project instead of the default.',
    matchesEverything: 'Matches every meeting',
    newRuleTitle: 'New meeting rule',
    nameHint: 'TFN scrums',
    noteHint: 'Meeting: {title}',
    notePlaceholders:
        'Placeholders: {title} {location} {organizer}. Empty uses the subject.',
    provider: (c, listen) =>
        Provider.of<MeetingRuleProvider>(c, listen: listen),
  );
}

/// Settings list of rules (work item or meeting, per [RuleKind]): an
/// auto-apply switch, then the rules in
/// evaluation order. Dragging a row changes which rule wins a tie.
class MappingRuleList extends StatelessWidget {
  final RuleKind kind;

  MappingRuleList({super.key, RuleKind? kind})
      : kind = kind ?? RuleKind.workItem;

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = kind.watch(context);
    final projects = context.watch<AssignmentProvider>().projects;
    final rules = provider.rules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: provider.autoApply,
          onChanged: (v) => kind.read(context).setAutoApply(v),
          title: Text(kind.autoApplyTitle),
          subtitle: Text(kind.autoApplySubtitle),
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: palette.brand,
        ),
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              kind.emptyText,
              style: TextStyle(fontSize: 12, color: palette.text3),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: rules.length,
            // onReorderItem replaces this on Flutter > 3.41, which is newer
            // than the SDK floor in pubspec.yaml — keep the compatible one.
            // ignore: deprecated_member_use
            onReorder: (oldIndex, newIndex) =>
                kind.read(context).reorder(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return _MappingRuleRow(
                key: ValueKey(rule.id),
                index: index,
                rule: rule,
                projects: projects,
                kind: kind,
              );
            },
          ),
        if (rules.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Rules are evaluated top to bottom; the first match wins.',
              style: TextStyle(fontSize: 11, color: palette.text3),
            ),
          ),
      ],
    );
  }
}

class _MappingRuleRow extends StatelessWidget {
  final int index;
  final MappingRule rule;
  final List<HarvestProject> projects;
  final RuleKind kind;

  const _MappingRuleRow({
    super.key,
    required this.index,
    required this.rule,
    required this.projects,
    required this.kind,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final project = projects.firstWhereOrNull((p) => p.id == rule.projectId);
    final task = project?.tasks.firstWhereOrNull((t) => t.id == rule.taskId);
    final targetMissing = projects.isNotEmpty && (project == null || task == null);

    final conditionSummary = rule.conditions.isEmpty
        ? kind.matchesEverything
        : rule.conditions
            .map((c) => c.summaryWith(kind.labelFor))
            .join('  ·  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_indicator, size: 18, color: palette.text4),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rule.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: rule.enabled ? palette.text : palette.text3,
                        ),
                      ),
                    ),
                    if (targetMissing) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: HarvestTokens.warn),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  conditionSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.text3),
                ),
                const SizedBox(height: 2),
                Text(
                  targetMissing
                      ? 'Target project or task is no longer assigned to you'
                      : '→ ${project?.name ?? 'Project ${rule.projectId}'}'
                          ' · ${task?.name ?? 'Task ${rule.taskId}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: targetMissing ? HarvestTokens.warn : palette.text2,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: rule.enabled,
            onChanged: (v) => kind.read(context).setEnabled(rule.id, v),
            activeThumbColor: palette.brand,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit rule',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                showMappingRuleDialog(context, existing: rule, kind: kind),
          ),
        ],
      ),
    );
  }
}

/// Opens the add/edit dialog. Pass [existing] to edit a rule in place, and
/// [kind] for a list other than the work item rules.
Future<void> showMappingRuleDialog(
  BuildContext context, {
  MappingRule? existing,
  RuleKind? kind,
}) async {
  final ruleKind = kind ?? RuleKind.workItem;
  final projects = context.read<AssignmentProvider>().projects;
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Load your Harvest projects before adding rules'),
      ),
    );
    return;
  }
  final provider = ruleKind.read(context);
  await showDialog<void>(
    context: context,
    builder: (_) => _MappingRuleDialog(
      existing: existing,
      projects: projects,
      kind: ruleKind,
      provider: provider,
    ),
  );
}

class _MappingRuleDialog extends StatefulWidget {
  final MappingRule? existing;
  final List<HarvestProject> projects;
  final RuleKind kind;
  final MappingRuleProvider provider;

  const _MappingRuleDialog({
    required this.existing,
    required this.projects,
    required this.kind,
    required this.provider,
  });

  @override
  State<_MappingRuleDialog> createState() => _MappingRuleDialogState();
}

class _MappingRuleDialogState extends State<_MappingRuleDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late List<MappingCondition> _conditions;
  late int _projectId;
  late int? _taskId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _noteController = TextEditingController(text: existing?.noteTemplate ?? '');
    _conditions =
        List.of(existing?.conditions ?? [widget.kind.firstCondition]);

    final fallback = widget.projects.first;
    final project = existing == null
        ? fallback
        : widget.projects.firstWhereOrNull((p) => p.id == existing.projectId) ??
            fallback;
    _projectId = project.id;
    _taskId = existing == null
        ? project.tasks.firstOrNull?.id
        : project.tasks.firstWhereOrNull((t) => t.id == existing.taskId)?.id ??
            project.tasks.firstOrNull?.id;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  HarvestProject get _project =>
      widget.projects.firstWhere((p) => p.id == _projectId);

  /// Returns an error message, or null when the rule is savable.
  String? _validate() {
    if (_nameController.text.trim().isEmpty) return 'Give the rule a name';
    if (_taskId == null) return 'This project has no tasks assigned';
    for (final c in _conditions) {
      if (c.value.trim().isEmpty) {
        return '"${widget.kind.labelFor(c.field)}" has no value';
      }
      if (c.operator == ConditionOperator.regex) {
        try {
          RegExp(c.value);
        } catch (_) {
          return 'Invalid regular expression: ${c.value}';
        }
      }
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final provider = widget.provider;
    final navigator = Navigator.of(context);
    final note = _noteController.text.trim();
    final existing = widget.existing;
    final rule = existing == null
        ? MappingRule(
            id: provider.newId(),
            name: _nameController.text.trim(),
            projectId: _projectId,
            taskId: _taskId!,
            conditions: _conditions,
            noteTemplate: note.isEmpty ? null : note,
          )
        : existing.copyWith(
            name: _nameController.text.trim(),
            projectId: _projectId,
            taskId: _taskId!,
            conditions: _conditions,
            noteTemplate: note.isEmpty ? null : note,
            clearNoteTemplate: note.isEmpty,
          );
    await provider.upsert(rule);
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final provider = widget.provider;
    final navigator = Navigator.of(context);
    await provider.delete(existing.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final tasks = _project.tasks;
    final kind = widget.kind;

    return AlertDialog(
      title: Text(widget.existing == null ? kind.newRuleTitle : 'Edit rule'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Rule name',
                  border: const OutlineInputBorder(),
                  hintText: kind.nameHint,
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              Text('When all of these match',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.text2)),
              const SizedBox(height: 6),
              if (_conditions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No conditions — this rule '
                    '${kind.matchesEverything.toLowerCase()}.',
                    style: TextStyle(fontSize: 11, color: HarvestTokens.warn),
                  ),
                ),
              for (var i = 0; i < _conditions.length; i++)
                _ConditionRow(
                  key: ValueKey(i),
                  condition: _conditions[i],
                  kind: kind,
                  onChanged: (c) => setState(() => _conditions[i] = c),
                  onRemove: () => setState(() => _conditions.removeAt(i)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add condition'),
                  onPressed: () =>
                      setState(() => _conditions.add(kind.addedCondition)),
                ),
              ),
              const SizedBox(height: 8),

              Text('Log to',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.text2)),
              const SizedBox(height: 6),
              DropdownButtonFormField<int>(
                initialValue: _projectId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Project',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: widget.projects
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _projectId = v;
                    _taskId = _project.tasks.firstOrNull?.id;
                  });
                },
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _taskId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Task',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: tasks
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _taskId = v),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: 'Note template (optional)',
                  border: const OutlineInputBorder(),
                  hintText: kind.noteHint,
                  helperText: kind.notePlaceholders,
                  helperMaxLines: 2,
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 12, color: HarvestTokens.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: HarvestTokens.error),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ConditionRow extends StatelessWidget {
  final MappingCondition condition;
  final RuleKind kind;
  final ValueChanged<MappingCondition> onChanged;
  final VoidCallback onRemove;

  const _ConditionRow({
    super.key,
    required this.condition,
    required this.kind,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<String>(
                  // A field outside this kind's set has no menu item and
                  // would assert — show the first field instead.
                  initialValue: kind.fields.contains(condition.field)
                      ? condition.field
                      : kind.fields.first,
                  isExpanded: true,
                  decoration: _denseDecoration('Field'),
                  items: kind.fields
                      .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(kind.labelFor(f),
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      v == null ? null : onChanged(condition.copyWith(field: v)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 4,
                child: DropdownButtonFormField<ConditionOperator>(
                  initialValue: condition.operator,
                  isExpanded: true,
                  decoration: _denseDecoration('Operator'),
                  items: ConditionOperator.values
                      .map((o) => DropdownMenuItem(
                            value: o,
                            child: Text(o.label,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => v == null
                      ? null
                      : onChanged(condition.copyWith(operator: v)),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Remove condition',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('${condition.field}-${condition.operator}'),
                  initialValue: condition.value,
                  style: const TextStyle(fontSize: 13),
                  decoration:
                      _denseDecoration(_valueHintFor(condition.operator)),
                  onChanged: (v) => onChanged(condition.copyWith(value: v)),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: 'Invert this condition',
                child: FilterChip(
                  label: const Text('not', style: TextStyle(fontSize: 12)),
                  selected: condition.negate,
                  onSelected: (v) => onChanged(condition.copyWith(negate: v)),
                  selectedColor: palette.brandTint,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static InputDecoration _denseDecoration(String label) => InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      );

  static String _valueHintFor(ConditionOperator op) => switch (op) {
        ConditionOperator.inList => 'Value — comma separated',
        ConditionOperator.underPath => r'Value — e.g. Contoso\Web',
        ConditionOperator.regex => 'Value — regular expression',
        _ => 'Value',
      };
}
