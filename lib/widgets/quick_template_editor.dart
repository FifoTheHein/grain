import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/project_assignment.dart';
import '../models/quick_template.dart';
import '../providers/assignment_provider.dart';
import '../providers/quick_template_provider.dart';
import '../theme/harvest_tokens.dart';

/// Settings list of quick templates, in the order the chips appear on Log Time.
class QuickTemplateList extends StatelessWidget {
  const QuickTemplateList({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = context.watch<QuickTemplateProvider>();
    final projects = context.watch<AssignmentProvider>().projects;
    final templates = provider.templates;

    if (templates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No templates yet. Add one for the work you log most often — it '
          'appears as a chip above the project picker on Log Time.',
          style: TextStyle(fontSize: 12, color: palette.text3),
        ),
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: templates.length,
      // onReorderItem replaces this on Flutter > 3.41, which is newer than the
      // SDK floor in pubspec.yaml — keep the compatible one.
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) =>
          context.read<QuickTemplateProvider>().reorder(oldIndex, newIndex),
      itemBuilder: (context, index) {
        final template = templates[index];
        return _TemplateRow(
          key: ValueKey(template.id),
          index: index,
          template: template,
          projects: projects,
        );
      },
    );
  }
}

class _TemplateRow extends StatelessWidget {
  final int index;
  final QuickTemplate template;
  final List<HarvestProject> projects;

  const _TemplateRow({
    super.key,
    required this.index,
    required this.template,
    required this.projects,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final project =
        projects.firstWhereOrNull((p) => p.id == template.projectId);
    final task = project?.tasks.firstWhereOrNull((t) => t.id == template.taskId);
    final targetMissing =
        projects.isNotEmpty && (project == null || task == null);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 8),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(Icons.drag_indicator, size: 18, color: palette.text4),
          ),
          const SizedBox(width: 6),
          Icon(template.icon, size: 18, color: template.color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        template.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              template.enabled ? palette.text : palette.text3,
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
                  targetMissing
                      ? 'Project or task is no longer assigned to you'
                      : '${project?.name ?? 'Project ${template.projectId}'}'
                          ' · ${task?.name ?? 'Task ${template.taskId}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: targetMissing ? HarvestTokens.warn : palette.text2,
                  ),
                ),
                if (template.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 2),
                  Text(
                    template.notes!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: palette.text3),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: template.enabled,
            onChanged: (v) =>
                context.read<QuickTemplateProvider>().setEnabled(template.id, v),
            activeThumbColor: palette.brand,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Edit template',
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                showQuickTemplateDialog(context, existing: template),
          ),
        ],
      ),
    );
  }
}

/// Opens the add/edit dialog. Pass [existing] to edit in place.
Future<void> showQuickTemplateDialog(
  BuildContext context, {
  QuickTemplate? existing,
}) async {
  final projects = context.read<AssignmentProvider>().projects;
  if (projects.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Load your Harvest projects before adding templates'),
      ),
    );
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _QuickTemplateDialog(existing: existing, projects: projects),
  );
}

class _QuickTemplateDialog extends StatefulWidget {
  final QuickTemplate? existing;
  final List<HarvestProject> projects;

  const _QuickTemplateDialog({required this.existing, required this.projects});

  @override
  State<_QuickTemplateDialog> createState() => _QuickTemplateDialogState();
}

class _QuickTemplateDialogState extends State<_QuickTemplateDialog> {
  late final TextEditingController _labelController;
  late final TextEditingController _notesController;
  late int _projectId;
  late int? _taskId;
  late int _iconIndex;
  late int _colorIndex;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');
    _iconIndex = existing?.iconIndex ?? 0;
    _colorIndex = existing?.colorIndex ?? 0;

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
    _labelController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  HarvestProject get _project =>
      widget.projects.firstWhere((p) => p.id == _projectId);

  Future<void> _save() async {
    if (_labelController.text.trim().isEmpty) {
      setState(() => _error = 'Give the template a label');
      return;
    }
    if (_taskId == null) {
      setState(() => _error = 'This project has no tasks assigned');
      return;
    }

    final provider = context.read<QuickTemplateProvider>();
    final navigator = Navigator.of(context);
    final notes = _notesController.text.trim();
    final existing = widget.existing;
    final template = existing == null
        ? QuickTemplate(
            id: provider.newId(),
            label: _labelController.text.trim(),
            projectId: _projectId,
            taskId: _taskId!,
            notes: notes.isEmpty ? null : notes,
            iconIndex: _iconIndex,
            colorIndex: _colorIndex,
          )
        : existing.copyWith(
            label: _labelController.text.trim(),
            projectId: _projectId,
            taskId: _taskId!,
            notes: notes.isEmpty ? null : notes,
            clearNotes: notes.isEmpty,
            iconIndex: _iconIndex,
            colorIndex: _colorIndex,
          );
    await provider.upsert(template);
    navigator.pop();
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final provider = context.read<QuickTemplateProvider>();
    final navigator = Navigator.of(context);
    await provider.delete(existing.id);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final color = kTemplateColors[_colorIndex];

    return AlertDialog(
      title: Text(widget.existing == null ? 'New template' : 'Edit template'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  border: OutlineInputBorder(),
                  hintText: 'PR Reviews',
                ),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

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
                items: _project.tasks
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(t.name, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _taskId = v),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Default notes (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Reviewing pull requests',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              Text('Icon',
                  style: TextStyle(fontSize: 12, color: palette.text2)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < kTemplateIcons.length; i++)
                    _PickerTile(
                      selected: i == _iconIndex,
                      color: color,
                      onTap: () => setState(() => _iconIndex = i),
                      child: Icon(kTemplateIcons[i],
                          size: 18,
                          color: i == _iconIndex ? color : palette.text2),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              Text('Colour',
                  style: TextStyle(fontSize: 12, color: palette.text2)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < kTemplateColors.length; i++)
                    _PickerTile(
                      selected: i == _colorIndex,
                      color: kTemplateColors[i],
                      onTap: () => setState(() => _colorIndex = i),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kTemplateColors[i],
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 20),
              Text('Preview',
                  style: TextStyle(fontSize: 12, color: palette.text2)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: palette.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(kTemplateIcons[_iconIndex], size: 15, color: color),
                      const SizedBox(width: 6),
                      Text(
                        _labelController.text.trim().isEmpty
                            ? 'Label'
                            : _labelController.text.trim(),
                        style: TextStyle(fontSize: 12, color: palette.text),
                      ),
                    ],
                  ),
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: HarvestTokens.error)),
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

class _PickerTile extends StatelessWidget {
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  final Widget child;

  const _PickerTile({
    required this.selected,
    required this.color,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: selected ? color.withValues(alpha: 0.14) : palette.surface2,
          border: Border.all(
            color: selected ? color : palette.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: child,
      ),
    );
  }
}
