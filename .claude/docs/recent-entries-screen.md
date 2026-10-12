# RecentEntriesScreen (`lib/screens/recent_entries_screen.dart`)

Stateless apart from its provider listener: listens to `TimeEntryProvider` via `addListener` in `didChangeDependencies` (not `initState`) to survive tab switches; triggers `AdoService.prefetchForEntries` on each change.

**Layout (top → bottom):**
1. Date nav row — `chevron_left` / tappable date label / `chevron_right` (capped at today)
2. `_WeekSummaryStrip` — Mon–Sun day chips + `WeeklyProgressRing`. Two variants: `_buildCompact` (narrow) and `_buildEmphasized` (≥ `HarvestTokens.kWideBreakpoint`); emphasized shows day-of-month numerals + per-day `LinearProgressIndicator` against `ProjectCategoryProvider.dailyGoalHours`
3. Entry list — flat `SliverList` of `TimeEntryCard`, sorted by `createdAt` desc. Per-project totals live on the Insights screen, not here
4. `_DailyProgressBar` — sticky bottom bar; goal from `ProjectCategoryProvider.dailyGoalHours`, `HarvestTokens.warn` color when over; when viewing today shows a tick marker at the expected position + "Expected: Xh Ym" label (proportional: `elapsedRatio × dailyGoalHours`)

**Private widgets (all in this file):**
- `_WeekSummaryStrip` — reads `weeklyGoalHours` and `dailyGoalHours` from `ProjectCategoryProvider`; `_DayData` holds per-day state
- `_DailyProgressBar` — reads `dailyGoalHours`, `workDayStart`, `workDayEnd` from `ProjectCategoryProvider`; accepts `isToday` to conditionally show expected time tick + label; shows "Xh Ym remaining" or "+Xh Ym over goal"
- **`lib/widgets/`** — `WorkItemPreview` fetches and renders a live ADO work item card (debounced 600 ms). `TimeEntryCard` renders an entry with an optional embedded ADO card.

**`TimeEntryCard` (`lib/widgets/time_entry_card.dart`)** — compact, one row:

- 38 px `DurationPill` (live and badged while running) · project code chip + task · one line of notes (ellipsis) · a single trailing action, Continue or Stop (`_TimerButton`; Continue disabled while another timer runs).
- **No edit button**: the whole card is an `InkWell` that pushes `EditTimeScreen`.
- **Running entry** gets a 1.5 px `palette.brand` border, since it can scroll out of view.
- **Work item entries** (`entry.adoReference != null`) keep the full `WorkItemChip` under the head line, tap-to-open included. The notes line goes through `workItemNotesLine` (`lib/models/entry_display.dart`): Log Time writes `{instance} Azure DevOps {type} #{id}` or `… #{id} - {typed}`, so a prefix-only note is hidden and a prefixed one shows only what was typed.
- **Imported meetings** (`externalReference.id` starting `kMeetingRefPrefix`) show a calendar icon and `HH:mm` start before the action, from `meetingStartLabel`: Harvest's `startedTime` when the account records it, otherwise the epoch seconds at the end of `GrainCalendar_{hash}_{epoch}` (the series occurrence, read as local time). A meeting linked to a work item carries the ADO reference instead, so it shows no marker.
- Pure helpers tested in `test/entry_display_test.dart`; the card in `test/time_entry_card_test.dart`.
