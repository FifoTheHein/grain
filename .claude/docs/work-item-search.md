# Work Item Search

Finds the work item instead of making you remember its number. The search icon
on the "Work Item #" field (Log Time and Edit Time) opens a picker over the
items assigned to you.

**Fetching (`AdoService.fetchAssignedWorkItems`)** — WIQL only ever returns
ids, so this is two calls: `POST /_apis/wit/wiql` for
`[System.AssignedTo] = @Me` ordered by changed date (excluding Closed, Removed
and Done unless `includeCompleted`), then a field-limited
`GET /_apis/wit/workitems?ids=…&fields=…` per 200 ids — ADO's batch ceiling.
Results cache per instance label until `refresh: true`; `isLoadingAssigned` and
`assignedError` expose the state to the picker. Fetched items also seed the
single-item cache, so the preview renders instantly on pick. Requires a PAT.

**Search (`lib/models/work_item_search.dart`)** — pure Dart, unit tested in
`test/work_item_search_test.dart`.

- `matchesWorkItem` is a case-insensitive substring match over id, title, type,
  state, project and tags. A leading `#` is stripped, so `#123` and `123` both
  work, and the id match is a substring too — `483` finds `13483`.
- `buildWorkItemTree` nests on `AdoWorkItem.parentId` (`System.Parent`). Only
  what was fetched gets nested: an item whose parent is missing from the set is
  simply a root, rather than triggering another round trip. Duplicate ids
  collapse onto the first occurrence, and a parent cycle degrades to roots
  rather than looping.
- `filterWorkItemTree` prunes to matches but keeps the ancestors of a match, so
  a matched Task still reads under its User Story. A node matching on its own
  is kept even when its children do not — and those children are dropped.
- `flattenTree` / `flattenWithDepth` render the forest as an indented list.

**Status filter** — board-style chips above the list: "All statuses" plus one
per state, each with its count, tapping the active chip clearing it.

- `availableStates` derives the chips from the fetched items rather than
  hard-coding them, so each project's process comes through as-is. Sorted
  alphabetically, not by count, so a chip does not jump position on refresh.
- `kHiddenFilterStates` (currently `blocked`) suppresses a chip without hiding
  the work: Blocked items are still listed under "All statuses" and still
  reachable by search.
- `kDefaultExcludedStates` (currently `design`) is the opposite trade — the
  state keeps its chip but drops out of "All statuses", for a bucket big enough
  to bury the rest of the backlog. `applyStateFilter` is what the picker calls:
  a selected chip means literally that state, including an excluded one, while
  no selection means everything except them. The count line names whatever was
  held back, so a missing work item is explained rather than mysterious.
- `kCompletedStates` / `excludeCompleted` drop finished work client-side. The
  WIQL already excludes Done, Closed and Removed server-side; this is the guard
  for a process that names finished work differently.
- The picker applies state before text, so the tree nests only what survived
  the filter and a task whose parent is in another state reads as a root.

**Picker (`lib/widgets/work_item_picker.dart`)** — `showWorkItemPicker` returns
the chosen id or null. Search field, Tree/Flat toggle, a refresh button, a
match count, and distinct empty states for "nothing assigned", "no matches" and
a failed fetch. Enter picks the only remaining match. Both screens drop the id
into the field and then run their normal `_onWorkItemChanged` path, so the
preview and (on Log Time) the mapping rules behave exactly as if it were typed.
