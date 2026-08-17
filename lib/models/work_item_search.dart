/// Client-side work item search and the parent/child tree it filters.
///
/// Pure Dart — no I/O, no Flutter — so it is unit tested directly in
/// `test/work_item_search_test.dart`. The fetch layer decides *which* items
/// exist; everything here only narrows and nests what it was given.
library;

import 'ado_work_item.dart';

/// True when [query] matches any of the fields you would plausibly type:
/// id, title, type, state, project or tags. Case-insensitive substring
/// matching throughout, and a leading `#` is ignored so `#123` and `123` both
/// find work item 123.
///
/// The id match is a substring too, so `34` finds `1234` — handy when you only
/// remember the tail of a number.
bool matchesWorkItem(AdoWorkItem item, String query) {
  final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^#'), '');
  if (q.isEmpty) return true;
  return item.id.toLowerCase().contains(q) ||
      item.title.toLowerCase().contains(q) ||
      (item.workItemType ?? '').toLowerCase().contains(q) ||
      item.state.toLowerCase().contains(q) ||
      (item.project ?? '').toLowerCase().contains(q) ||
      item.tags.any((t) => t.toLowerCase().contains(q));
}

/// Flat filter, preserving the incoming order.
List<AdoWorkItem> filterWorkItems(List<AdoWorkItem> items, String query) =>
    items.where((i) => matchesWorkItem(i, query)).toList();

/// Finished states. The WIQL query already excludes these server-side; this is
/// the client-side guard, so a process that reports a finished item some other
/// way still never reaches the picker.
const kCompletedStates = <String>{'done', 'closed', 'removed', 'completed'};

/// Drops anything in a [kCompletedStates] state.
List<AdoWorkItem> excludeCompleted(List<AdoWorkItem> items) => items
    .where((i) => !kCompletedStates.contains(i.state.trim().toLowerCase()))
    .toList();

/// States the picker never offers as a filter chip, matched case-insensitively.
/// Items in these states are still listed under "All statuses" — this only
/// suppresses the shortcut.
const kHiddenFilterStates = <String>{'blocked'};

/// States held back from "All statuses", matched case-insensitively.
///
/// The opposite trade to [kHiddenFilterStates]: these keep their chip but drop
/// out of the default view, for a state that carries so much of the backlog
/// that it buries everything else. Selecting the chip still shows them.
const kDefaultExcludedStates = <String>{'design'};

/// How many items sit in each state, keyed by the state as ADO spelled it.
Map<String, int> stateCounts(List<AdoWorkItem> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final state = item.state.trim();
    if (state.isEmpty) continue;
    counts[state] = (counts[state] ?? 0) + 1;
  }
  return counts;
}

/// The states offered as filter chips: whatever the fetched items are actually
/// in, minus [kHiddenFilterStates], sorted alphabetically.
///
/// Derived from the data rather than hard-coded, so it follows each project's
/// process. Alphabetical rather than by count so a chip does not jump position
/// when the counts change under a refresh.
List<String> availableStates(List<AdoWorkItem> items) {
  final states = stateCounts(items)
      .keys
      .where((s) => !kHiddenFilterStates.contains(s.toLowerCase()))
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return states;
}

/// Narrows to a single state. A null or empty [state] means "all statuses",
/// which here really is every state — see [applyStateFilter] for the version
/// the picker uses.
List<AdoWorkItem> filterByState(List<AdoWorkItem> items, String? state) {
  if (state == null || state.trim().isEmpty) return List.of(items);
  final target = state.trim().toLowerCase();
  return items.where((i) => i.state.trim().toLowerCase() == target).toList();
}

/// What the picker lists for the selected chip.
///
/// With a chip selected this is just that state — including a
/// [kDefaultExcludedStates] one, so selecting it is how you reach those items.
/// With no chip selected it is everything except those states, so one enormous
/// bucket cannot bury the rest of the backlog.
List<AdoWorkItem> applyStateFilter(List<AdoWorkItem> items, String? state) {
  if (state != null && state.trim().isNotEmpty) {
    return filterByState(items, state);
  }
  return items
      .where((i) =>
          !kDefaultExcludedStates.contains(i.state.trim().toLowerCase()))
      .toList();
}

/// A work item with whichever of its children were also fetched.
class WorkItemNode {
  final AdoWorkItem item;
  final List<WorkItemNode> children;

  const WorkItemNode({required this.item, this.children = const []});
}

/// Builds the parent/child forest over a flat list.
///
/// Only what the fetch layer returned gets nested: an item whose parent is not
/// in the set is simply a root, rather than triggering another round trip.
/// Siblings keep their incoming order, a repeated id collapses onto its first
/// occurrence, and a parent cycle degrades to roots rather than looping.
List<WorkItemNode> buildWorkItemTree(List<AdoWorkItem> items) {
  final byId = <String, AdoWorkItem>{};
  final unique = <AdoWorkItem>[];
  for (final item in items) {
    if (byId.containsKey(item.id)) continue;
    byId[item.id] = item;
    unique.add(item);
  }

  final childrenOf = <String, List<AdoWorkItem>>{};
  final roots = <AdoWorkItem>[];
  for (final item in unique) {
    final parentId = item.parentId;
    if (parentId == null ||
        parentId == item.id ||
        !byId.containsKey(parentId) ||
        _isCyclic(item, byId)) {
      roots.add(item);
      continue;
    }
    childrenOf.putIfAbsent(parentId, () => []).add(item);
  }

  WorkItemNode toNode(AdoWorkItem item) => WorkItemNode(
        item: item,
        children: (childrenOf[item.id] ?? const []).map(toNode).toList(),
      );

  return roots.map(toNode).toList();
}

/// Walks up the parent chain looking for a loop back to [start].
bool _isCyclic(AdoWorkItem start, Map<String, AdoWorkItem> byId) {
  final seen = <String>{start.id};
  var current = start.parentId;
  while (current != null) {
    if (!seen.add(current)) return true;
    current = byId[current]?.parentId;
  }
  return false;
}

/// Prunes the forest to matching items while keeping the ancestors of a match,
/// so a matched Task still reads under its User Story. A node that matches on
/// its own is kept even when none of its children do — its non-matching
/// children are dropped with them. An empty query is a no-op.
List<WorkItemNode> filterWorkItemTree(
    List<WorkItemNode> nodes, String query) {
  if (query.trim().isEmpty) return List.of(nodes);

  WorkItemNode? prune(WorkItemNode node) {
    final children =
        node.children.map(prune).whereType<WorkItemNode>().toList();
    if (children.isEmpty && !matchesWorkItem(node.item, query)) return null;
    return WorkItemNode(item: node.item, children: children);
  }

  return nodes.map(prune).whereType<WorkItemNode>().toList();
}

/// Depth-first flatten — each parent immediately followed by its descendants.
List<AdoWorkItem> flattenTree(List<WorkItemNode> nodes) {
  final out = <AdoWorkItem>[];
  void walk(List<WorkItemNode> list) {
    for (final node in list) {
      out.add(node.item);
      walk(node.children);
    }
  }

  walk(nodes);
  return out;
}

/// Depth-first flatten that keeps each item's depth, for indenting a list.
List<({AdoWorkItem item, int depth})> flattenWithDepth(
    List<WorkItemNode> nodes) {
  final out = <({AdoWorkItem item, int depth})>[];
  void walk(List<WorkItemNode> list, int depth) {
    for (final node in list) {
      out.add((item: node.item, depth: depth));
      walk(node.children, depth + 1);
    }
  }

  walk(nodes, 0);
  return out;
}
