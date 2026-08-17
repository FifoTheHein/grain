# SettingsScreen (`lib/screens/settings_screen.dart`)

State: token + accountId `TextEditingController`s, `_obscureToken`, `_defaultProjectId`, `_defaultTaskId`, `_autoRefreshIntervalMinutes` (all loaded from SharedPreferences in `_load()`). No provider listeners — reads on demand.

**Sections (scrollable column):**
1. **Harvest Credentials** — API token (obscured) + Account ID fields
2. **Default Project** — `_DefaultProjectDropdown` → `_DefaultTaskDropdown` (only shown when project selected); stored as `default_project_id` / `default_task_id` in prefs
3. **Background Refresh** — interval dropdown (5/15/30/60 min); applied on save via `TimeEntryProvider.setRefreshInterval`
4. **Project Categories** — `_ProjectCategoryRow` per project; edit dialog has 12-color palette + code (≤5 chars); persisted via `ProjectCategoryProvider.setCategory`
5. **Weekly Goal** — free-text hours field; calls `ProjectCategoryProvider.setWeeklyGoal` on every keystroke
6. **Work Day** — start time + end time (tappable, `showTimePicker`), break hours field, and the Insights gap threshold dropdown; calls `setWorkDayStart` / `setWorkDayEnd` / `setBreakHours` / `setMinGapMinutes`; derived label shows "= Xh work day" live
7. **Azure DevOps Instances** — `_AdoInstanceList`; add/edit via `_showAdoDialog`; each row shows label, baseUrl, PAT presence dot, and Harvest GUID status (check/warn icon); GUID editable via `_showEditGuidDialog` → `AdoService.setHarvestGuid`
8. **Work Item Mapping Rules** — `MappingRuleList` (`lib/widgets/mapping_rule_editor.dart`): auto-apply switch, drag-to-reorder rule rows, add/edit via `showMappingRuleDialog`; see `mapping-rules.md`
9. **Quick Templates** — `QuickTemplateList` (`lib/widgets/quick_template_editor.dart`): drag-to-reorder template rows, add/edit via `showQuickTemplateDialog`; see `quick-templates.md`
10. **Action buttons** — Save & Reload, Clear Cache & Refresh, Migrate ADO References (streams progress via `_MigrationProgressDialog`), Reset to Defaults

**Private widgets (all in this file):**
- `_SectionHeader` — title + optional trailing action widget
- `_AdoInstanceList` — watches `AdoInstanceProvider` + `AdoService`; "Reset to Defaults" resets to `AppConfig` defaults
- `_DefaultProjectDropdown` / `_DefaultTaskDropdown` — guard against stale selected IDs missing from current project list
- `_ProjectCategoryRow` — color swatch + code badge + edit button; opens `_showEditCategoryDialog` with `StatefulBuilder` dialog
- `_MigrationProgressDialog` — subscribes to `Stream<({int done, int total, int failed})>`; shows indeterminate → determinate `LinearProgressIndicator`
