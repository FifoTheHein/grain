import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/mapping_rule.dart';
import '../models/project_assignment.dart';
import '../providers/assignment_provider.dart';
import '../providers/mapping_rule_provider.dart';
import '../theme/harvest_tokens.dart';

/// Settings list of mapping rules: an auto-apply switch, then the rules in
/// evaluation order. Dragging a row changes which rule wins a tie.
class MappingRuleList extends StatelessWidget {
  const MappingRuleList({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = context.watch<MappingRuleProvider>();
    final projects = context.watch<AssignmentProvider>().projects;
    final rules = provider.rules;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          value: provider.autoApply,
          onChanged: (v) =>
              context.read<MappingRuleProvider>().setAutoApply(v),
          title: const Text('Auto-select project & task from work items'),
          subtitle: const Text(
              'Applies the first matching rule when a work item loads'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: HarvestTokens.brand,
        ),
        if (rules.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No rules yet. Add one to have Grain pick the Harvest project and '
              'task for a work item automatically.',
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
            onReorder: (oldIndex, newIndex) => context
                .read<MappingRuleProvider>()
                .reorder(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final rule = rules[index];
              return _MappingRuleRow(
                key: ValueKey(rule.id),
                index: index,
                rule: rule,
                projects: projects,
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

  const _MappingRuleRow({
    super.key,
    required this.index,
    required this.rule,
    required this.projects,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final project = projects.firstWhereOrNull((p) => p.id == rule.projectId);
    final task = project?.tasks.firstWhereOrNull((t) => t.id == rule.taskId);
    final targetMissing = projects.isNotEmpty && (project == null || task == null);

    final conditionSummary = rule.conditions.isEmpty
        ? 'Matches every work item'
        : rule.conditions.map((c) => c.summary).join('  ·  ');

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
            onChanged: (v) =>
                context.read<MappingRuleProvider>().setEnabled(rule.id, v),
            activeThumbColor: HarvestTokens.brand,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit rule',
            visualDensity: VisualDensity.compact,
            onPressed: () => showMappingRuleDialog(context, existing: rule),
          ),
        ],
      ),
    );
  }
}

/// Opens the add/edit dialog. Pass [existing] to edit a rule in place.
Future<void> showMappingRuleDialog(
  BuildContext context, {
  MappingRule? existing,
}) async {
  final projects = context.read<AssignmentProvider>().projects;
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Load your Harvest projects before adding rules'),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _MappingRuleDialog(existing: existing, projects: projects),
  );
}

class _MappingRuleDialog extends StatefulWidget {
  final MappingRule? existing;
  final List<HarvestProject> projects;

  const _MappingRuleDialog({required this.existing, required this.projects});

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
    _conditions = List.of(existing?.conditions ??
        const [
          MappingCondition(
            field: WorkItemField.areaPath,
            operator: ConditionOperator.underPath,
            value: '',
          ),
        ]);

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
        return '"${WorkItemField.labelFor(c.field)}" has no value';
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
    final provider = context.read<MappingRuleProvider>();
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
    final provider = context.read<MappingRuleProvider>();
    final navigator = Navigator.of(context);
    await provider.delete(existing.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final tasks = _project.tasks;

    return AlertDialog(
      title: Text(widget.existing == null ? 'New mapping rule' : 'Edit rule'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Rule name',
                  border: OutlineInputBorder(),
                  hintText: 'Platform team bugs',
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
                    'No conditions — this rule matches every work item.',
                    style: TextStyle(fontSize: 11, color: HarvestTokens.warn),
                  ),
                ),
              for (var i = 0; i < _conditions.length; i++)
                _ConditionRow(
                  key: ValueKey(i),
                  condition: _conditions[i],
                  onChanged: (c) => setState(() => _conditions[i] = c),
                  onRemove: () => setState(() => _conditions.removeAt(i)),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add condition'),
                  onPressed: () => setState(() => _conditions.add(
                        const MappingCondition(
                          field: WorkItemField.workItemType,
                          operator: ConditionOperator.equals,
                          value: '',
                        ),
                      )),
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
                decoration: const InputDecoration(
                  labelText: 'Note template (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Investigating {type} {id}: {title}',
                  helperText:
                      'Placeholders: {id} {title} {type} {state} {project} '
                      '{areaPath} {iterationPath} {assignedTo}',
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
  final ValueChanged<MappingCondition> onChanged;
  final VoidCallback onRemove;

  const _ConditionRow({
    super.key,
    required this.condition,
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
                  initialValue: condition.field,
                  isExpanded: true,
                  decoration: _denseDecoration('Field'),
                  items: WorkItemField.all
                      .map((f) => DropdownMenuItem(
                            value: f,
                            child: Text(WorkItemField.labelFor(f),
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
