import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/project_assignment.dart';
import '../providers/assignment_provider.dart';

class ProjectTaskSelector extends StatelessWidget {
  const ProjectTaskSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssignmentProvider>();

    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.projects.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDropdown<HarvestProject>(
          context: context,
          label: 'Project',
          selected: provider.selectedProject,
          items: provider.projects,
          itemLabel: (p) =>
              p.code.isNotEmpty ? '${p.code} — ${p.name}' : p.name,
          onChanged: (p) =>
              context.read<AssignmentProvider>().selectProject(p),
        ),
        const SizedBox(height: 16),
        _buildDropdown<HarvestTask>(
          context: context,
          label: 'Task',
          selected: provider.selectedTask,
          items: provider.selectedProject?.tasks ?? [],
          itemLabel: (t) => t.name,
          onChanged: (t) =>
              context.read<AssignmentProvider>().selectTask(t),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required BuildContext context,
    required String label,
    required T? selected,
    required List<T> items,
    required String Function(T) itemLabel,
    required void Function(T) onChanged,
  }) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: selected,
          isDense: true,
          isExpanded: true,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(itemLabel(item)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}
