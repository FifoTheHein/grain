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

  /// Null means "all statuses".
  String? _state;

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

    // Belt and braces: the WIQL already excludes finished work, but a process
    // with its own naming should not be able to leak a Done item in here.
    final all = excludeCompleted(
        adoService.getCachedAssigned(label) ?? const <AdoWorkItem>[]);
    final loading = adoService.isLoadingAssigned(label);
    final error = adoService.assignedError(label);

    // State first, then text — so the tree nests only what survived the state
    // filter, and a task whose parent is in another state reads as a root.
    final inState = applyStateFilter(all, _state);
    final rows = _asTree
        ? flattenWithDepth(
            filterWorkItemTree(buildWorkItemTree(inState), _query))
        : filterWorkItems(inState, _query)
            .map((i) => (item: i, depth: 0))
            .toList();
    final counts = stateCounts(all);

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
            if (availableStates(all).isNotEmpty) ...[
              const SizedBox(height: 8),
              _StateFilterBar(
                states: availableStates(all),
                counts: counts,
                selected: _state,
                onSelected: (s) => setState(() => _state = s),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                // Expanded, not Flexible + Spacer: a Spacer is flex: 1 too, so
                // the two split the free space evenly and the text wrapped
                // with half the row sitting empty beside it.
                Expanded(
                  child: Tooltip(
                    // Only reachable when the row is too narrow even for this.
                    message: loading && all.isEmpty
                        ? 'Loading work items'
                        : _countTooltip(
                            shown: rows.length,
                            inView: inState.length,
                            hidden: _state == null
                                ? all.length - inState.length
                                : 0,
                          ),
                    child: Text(
                      loading && all.isEmpty
                          ? 'Loading…'
                          : _countLabel(
                              shown: rows.length,
                              inView: inState.length,
                              hidden: _state == null
                                  ? all.length - inState.length
                                  : 0,
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.text3),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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

  static String _excludedStateNames() => kDefaultExcludedStates
      .map((s) => s[0].toUpperCase() + s.substring(1))
      .join(', ');

  /// Says what is on screen, and owns up to anything held back by default so a
  /// missing work item is explained rather than mysterious.
  static String _countLabel({
    required int shown,
    required int inView,
    required int hidden,
  }) {
    final base = '$shown of $inView assigned to you';
    if (hidden == 0) return base;
    return '$base · $hidden ${_excludedStateNames()} hidden';
  }

  /// The unabbreviated version, shown on hover or long press.
  static String _countTooltip({
    required int shown,
    required int inView,
    required int hidden,
  }) {
    final base = '$shown of $inView work items assigned to you';
    if (hidden == 0) return base;
    return '$base · $hidden more in ${_excludedStateNames()}, '
        'hidden until you select that status';
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

/// Board-style status chips: "All statuses" plus one per state present in the
/// fetched items, each with its count.
class _StateFilterBar extends StatelessWidget {
  final List<String> states;
  final Map<String, int> counts;
  final String? selected;
  final ValueChanged<String?> onSelected;

  const _StateFilterBar({
    required this.states,
    required this.counts,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    // "All statuses" counts what it actually shows, so it does not advertise a
    // number that includes the states held back from the default view.
    final total = counts.entries
        .where((e) =>
            !kDefaultExcludedStates.contains(e.key.trim().toLowerCase()))
        .fold<int>(0, (sum, e) => sum + e.value);
    // Chips wrap onto as many rows as they need, capped at roughly three so a
    // process with a lot of states cannot crowd out the list; past that the
    // block scrolls.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 116),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _StateChip(
              label: 'All statuses',
              count: total,
              selected: selected == null,
              onTap: () => onSelected(null),
            ),
            for (final state in states)
              _StateChip(
                label: state,
                count: counts[state] ?? 0,
                selected: selected?.toLowerCase() == state.toLowerCase(),
                // Tapping the active chip clears it, back to all statuses.
                onTap: () => onSelected(
                    selected?.toLowerCase() == state.toLowerCase()
                        ? null
                        : state),
              ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _StateChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    // No outer padding — the Wrap owns the gaps between chips.
    return Material(
      color: selected ? palette.brandTint : palette.surface2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? HarvestTokens.brand : palette.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? HarvestTokens.brand600 : palette.text,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? HarvestTokens.brand600 : palette.text3,
                ),
              ),
            ],
          ),
        ),
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
