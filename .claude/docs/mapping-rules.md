# Work Item Mapping Rules

Auto-selects the Harvest project/task from the linked ADO work item, so a
recurring "this area path always goes to that project" decision is made once in
Settings instead of on every entry.

**Model (`lib/models/mapping_rule.dart`)** — pure Dart, no Flutter, unit tested
in `test/mapping_rule_test.dart`.

- `MappingCondition { field, operator, value, negate }`. `field` is one of the
  `WorkItemField` constants (`project`, `iterationPath`, `areaPath`,
  `workItemType`, `state`, `tags`, `title`, `assignedTo`, `id`).
- `ConditionOperator`: `equals`, `contains`, `startsWith`, `regex`, `inList`
  (comma-separated), `underPath` (segment-wise path prefix, `\` or `/`). All
  comparisons are case-insensitive and trimmed; a malformed regex never matches.
- `MappingRule { id, name, priority, enabled, conditions, projectId, taskId,
  noteTemplate }`. Conditions are ANDed — an empty list matches everything.
- `resolveMapping(rules, context)` returns the first enabled rule by ascending
  `priority`. A `MatchContext` is `Map<String, Object?>` where a list value
  (tags) matches if any element does; a missing field never matches.
- `renderNoteTemplate` expands `{id} {title} {type} {state} {project}
  {areaPath} {iterationPath} {assignedTo}`; unknown/unset placeholders are left
  as-is.

**Provider (`lib/providers/mapping_rule_provider.dart`)** — CRUD, `reorder`
(rewrites priorities to list order), and the `autoApply` toggle. Persists to
`mapping_rules_v1` / `mapping_rules_enabled` in SharedPreferences. `match()`
respects `autoApply`; `matchIgnoringToggle()` does not.

**Work item fields** — `AdoWorkItem` carries `project`, `areaPath`,
`iterationPath`, `assignedToName` and `tags` (ADO returns tags as one
`;`-separated string), exposed as `matchContext`. `AdoService.fetchWorkItem`
requests the matching `System.*` fields in its `$select`.

**Apply (`LogTimeScreen`)** — `_maybeApplyMapping` runs when a work item
resolves (cache hit or fetch). It applies at most once per
`instanceLabel:workItemId` so a rebuild never overrides a manual change, skips
rules whose project/task are no longer assigned, and only prefills notes when
the field is empty. `_MappingAppliedBanner` names the rule and offers Undo,
which restores the previous project/task/notes via
`AssignmentProvider.restoreSelection`.

**Edit (`lib/widgets/mapping_rule_editor.dart`)** — `MappingRuleList` (settings
section: auto-apply switch, drag-to-reorder rows, per-rule enable switch) and
`showMappingRuleDialog` (name, condition builder with a `not` chip per row,
project/task dropdowns, note template). Save validates non-empty values and
compiles any regex.
