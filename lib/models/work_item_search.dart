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
