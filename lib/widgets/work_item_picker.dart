import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';
import '../models/work_item_search.dart';
import '../services/ado_service.dart';
import '../theme/harvest_palette.dart';
import '../theme/harvest_tokens.dart';

/// Opens the picker for [instance] and returns the chosen work item id, or
/// null when dismissed.
Future<String?> showWorkItemPicker(
  BuildContext context, {
  required AdoInstance instance,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _WorkItemPickerDialog(instance: instance),
  );
}

class _WorkItemPickerDialog extends StatefulWidget {
  final AdoInstance instance;

  const _WorkItemPickerDialog({required this.instance});

  @override
  State<_WorkItemPickerDialog> createState() => _WorkItemPickerDialogState();
}

class _WorkItemPickerDialogState extends State<_WorkItemPickerDialog> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';
  bool _asTree = true;

  @override
  void initState() {
    super.initState();
    // Fetch on open; the service serves its cache unless asked to refresh.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdoService>().fetchAssignedWorkItems(widget.instance);
      _searchFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final adoService = context.watch<AdoService>();
    final label = widget.instance.label;

    final all = adoService.getCachedAssigned(label) ?? const <AdoWorkItem>[];
    final loading = adoService.isLoadingAssigned(label);
    final error = adoService.assignedError(label);

    final rows = _asTree
        ? flattenWithDepth(
            filterWorkItemTree(buildWorkItemTree(all), _query))
        : filterWorkItems(all, _query)
            .map((i) => (item: i, depth: 0))
            .toList();

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Work items · $label')),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh from Azure DevOps',
            onPressed: loading
                ? null
                : () => context
                    .read<AdoService>()
                    .fetchAssignedWorkItems(widget.instance, refresh: true),
          ),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              decoration: InputDecoration(
                hintText: 'Search id, title, type, state or tag',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) {
                // Enter picks the only remaining match.
                if (rows.length == 1) Navigator.pop(context, rows.first.item.id);
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  loading && all.isEmpty
                      ? 'Loading…'
                      : '${rows.length} of ${all.length} assigned to you',
                  style: TextStyle(fontSize: 11, color: palette.text3),
                ),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.account_tree_outlined, size: 15),
                      label: Text('Tree', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.list, size: 15),
                      label: Text('Flat', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {_asTree},
                  onSelectionChanged: (s) => setState(() => _asTree = s.first),
                  style: SegmentedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    selectedBackgroundColor: palette.brandTint,
                    selectedForegroundColor: HarvestTokens.brand600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildBody(
                context,
                rows: rows,
                all: all,
                loading: loading,
                error: error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required List<({AdoWorkItem item, int depth})> rows,
    required List<AdoWorkItem> all,
    required bool loading,
    required String? error,
  }) {
    final palette = HarvestTokens.of(context);

    if (loading && all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && all.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not load work items',
        detail: error,
      );
    }
    if (all.isEmpty) {
      return const _Message(
        icon: Icons.inbox_outlined,
        title: 'Nothing assigned to you',
        detail: 'This searches work items assigned to you that are not '
            'Closed, Removed or Done.',
      );
    }
    if (rows.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        title: 'No matches',
        detail: 'Nothing assigned to you matches “$_query”.',
      );
    }

    return Scrollbar(
      child: ListView.builder(
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final row = rows[index];
          return _WorkItemRow(
            item: row.item,
            depth: row.depth,
            onTap: () => Navigator.pop(context, row.item.id),
            palette: palette,
          );
        },
      ),
    );
  }
}

class _WorkItemRow extends StatelessWidget {
  final AdoWorkItem item;
  final int depth;
  final VoidCallback onTap;
  final HarvestPalette palette;

  const _WorkItemRow({
    required this.item,
    required this.depth,
    required this.onTap,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(8.0 + depth * 20, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (depth > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Icon(Icons.subdirectory_arrow_right,
                    size: 13, color: palette.text4),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: palette.text),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '#${item.id}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: palette.text2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          [
                            if (item.workItemType != null) item.workItemType!,
                            item.state,
                            if (item.tags.isNotEmpty) item.tags.join(', '),
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              TextStyle(fontSize: 11, color: palette.text3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: palette.text4),
            const SizedBox(height: 10),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text)),
            const SizedBox(height: 6),
            Text(detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, color: palette.text3, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
