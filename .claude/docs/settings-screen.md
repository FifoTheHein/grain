# SettingsScreen (`lib/screens/settings_screen.dart`)

A short list of groups, each opening its own page. `SettingsGroup` (an enum in
this file) defines the order, titles, icons and the page each one builds.

**Layout** — a `LayoutBuilder` on the screen's own width, against
`HarvestTokens.kWideBreakpoint`:

- **Narrow:** the group list and a page take turns. `_selected` null shows the
  list; a page gets a `_PageHeader` with a back arrow, and a `PopScope` turns
  the system back gesture into "back to the list" rather than leaving the app.
- **Wide:** the list is a 240 px sidebar beside the selected page, which
  defaults to Harvest account.

The list ends with `AppVersionLabel` (`lib/widgets/app_version_label.dart`),
"Grain 1.2.5 (build 8)" from `package_info_plus`: the Android package on a
phone, the web build's `version.json` in a browser. Both come from
`pubspec.yaml` at build time, so a version bump needs no other edit. It
renders nothing until the lookup returns, or if it fails. On Android the
build number is the APK's versionCode, which `--split-per-abi` offsets by 1000
per processor type (arm64-v8a's build 9 is 2009), so `formatAppVersion` drops
the thousands there.

Each list row shows a live one-line summary built in `_summaryFor` from the
providers ("2 instances · 2 rules", "Auto-log on · 3 meeting rules"), so the
list says where things stand without opening anything.

**Saving** — every page saves as you change it. The one exception is the
Harvest credentials: a half-typed token would fail every request, so they wait
for **Save & reconnect**, which also reloads projects and entries. There is no
page-wide Save button any more.

**Pages (`lib/screens/settings/`)**, sharing `settings_shared.dart`
(`SettingsSectionHeader`, `SettingsSectionDivider`, `SettingsHint`,
`SettingsPageBody`):

1. **Harvest account** (`account_settings.dart`) — token (obscured), account
   ID, user ID, Save & reconnect; refresh interval, applied immediately via
   `TimeEntryProvider.setRefreshInterval`
2. **Time tracking** (`time_tracking_settings.dart`) — Log Time default
   project/task, written to `default_project_id` / `default_task_id` on pick;
   weekly goal, work day start/end/break with the derived "= Xh work day", and
   the Insights gap threshold (`ProjectCategoryProvider`); Quick Templates
   (`QuickTemplateList`, see `quick-templates.md`)
3. **Azure DevOps** (`ado_settings.dart`) — `_AdoInstanceList` with add/edit via
   `showAdoInstanceDialog`, PAT dot and Harvest GUID status (editable via
   `_showEditGuidDialog` → `AdoService.setHarvestGuid`); the Completed Work
   switch (`ado_update_completed_work`, saved on toggle); Work Item Rules
   (`MappingRuleList`, see `mapping-rules.md`)
4. **Calendar** (`calendar_settings.dart`) — `CalendarImportSettings` and the
   Meeting Rules list (`MappingRuleList(kind: RuleKind.meeting)`); see
   `calendar-import.md`
5. **Appearance** (`appearance_settings.dart`) — theme mode, palette selector
   (see `theming.md`), and project colours/codes (`_ProjectCategoryRow`, 12-colour
   edit dialog, `ProjectCategoryProvider.setCategory`)
6. **Maintenance** (`maintenance_settings.dart`) — Clear cache & refresh,
   Migrate ADO references (progress via `_MigrationProgressDialog`), Reset to
   defaults (confirms first; clears credentials, Log Time default, refresh
   interval and Completed Work, keeping rules, templates, instances, calendar
   and appearance). The storage footer reads "this browser" on the web and
   "this device" on Android.

**Tests** — `test/widget_test.dart` pumps the screen with every provider it
reads (Harvest and ADO behind a `MockClient`) and checks the list, the version line, opening and
backing out of every group, the Reset confirmation, and the wide sidebar.
