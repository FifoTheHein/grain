# Quick Templates

One-tap launchers for recurring work ("PR Reviews", "Standup"): a chip row above
the project picker on Log Time that fills in project, task and default notes.
Tapping a chip only fills the form — nothing is submitted.

**Model (`lib/models/quick_template.dart`)** — `QuickTemplate { id, label,
projectId, taskId, notes, iconIndex, colorIndex, sortOrder, enabled }`, unit
tested in `test/quick_template_test.dart`.

- `iconIndex` / `colorIndex` are indices into the `kTemplateIcons` and
  `kTemplateColors` const lists, clamped on read so a stored template survives
  the palette changing length.
- Icons are stored as an index rather than a codepoint on purpose: the web
  release build tree-shakes icons and rejects `IconData` built from a runtime
  value, so every icon has to appear as a `const` in the source.

**Provider (`lib/providers/quick_template_provider.dart`)** — CRUD, `reorder`
(rewrites `sortOrder` to list order), `setEnabled`, and `enabledTemplates` for
the chip row. Persists to `quick_templates_v1` in SharedPreferences.

**Chip row (`lib/widgets/quick_template_bar.dart`)** — `QuickTemplateBar`
renders nothing when no templates are enabled, so the form is untouched for
anyone who never sets one up. A chip is highlighted when its project and task
match the current selection, and struck through and disabled when that
project/task is no longer assigned to the user.

**Apply (`LogTimeScreen._applyTemplate`)** — project and task always win, since
the tap is an explicit choice. Notes are only overwritten when the field is
empty or still holds another template's notes, tracked by
`_notesFromTemplateId`; typing into the field clears that marker so what you
wrote is never clobbered. Applying a template also dismisses any mapping-rule
banner, since the manual pick supersedes it.

**Edit (`lib/widgets/quick_template_editor.dart`)** — `QuickTemplateList`
(settings section: drag-to-reorder rows, per-template enable switch) and
`showQuickTemplateDialog` (label, project/task dropdowns, default notes, icon
and colour pickers, live chip preview).
