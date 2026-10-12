# RecentEntriesScreen (`lib/screens/recent_entries_screen.dart`)

Stateless apart from its provider listener: listens to `TimeEntryProvider` via `addListener` in `didChangeDependencies` (not `initState`) to survive tab switches; triggers `AdoService.prefetchForEntries` on each change.

**Layout (top → bottom):**
1. `_DateHeader` — `chevron_left` (+ a **Today** jump whenever another day is showing) / tappable label opening the picker / `chevron_right`. The label comes from `dayHeading`: "Today", "Tomorrow" or the weekday over "Mon 12 Oct 2026", with an `UpcomingTag` from tomorrow on and " · in N days" from two days out
2. `_WeekSummaryStrip` — Mon–Sun day tiles + `WeeklyProgressRing`. Two variants: `_buildCompact` (narrow: abbreviation, date number, hours) and `_buildEmphasized` (≥ `HarvestTokens.kWideBreakpoint`, adding a per-day `LinearProgressIndicator` against `ProjectCategoryProvider.dailyGoalHours`). Both take their colours from `_DayStyle`: the selected day (today or earlier) is a solid `brand` tile with `onBrand` ink; today, unselected, has its number in `palette.brandInkOn(background)` and a dot under it; future days fade to `kFutureDayOpacity` (0.38) and days past the cap to `kBeyondCapDayOpacity` (0.16), both by colour rather than an `Opacity` layer (which clipped label tops on Android); a selected future day gets a `DashedBorder` instead of the fill
3. Entry list — flat `SliverList` of `TimeEntryCard`, sorted by `createdAt` desc. Per-project totals live on the Insights screen, not here. On a future day a dashed "Logged ahead" note sits above the entries, and an empty future day shows `_EmptyFutureDay` with **Log time for Thu 15 Oct**
4. `_DailyProgressBar` — sticky bottom bar; goal from `ProjectCategoryProvider.dailyGoalHours`, `HarvestTokens.warn` color when over; when viewing today shows a tick marker at the expected position + "Expected: Xh Ym" label (proportional: `elapsedRatio × dailyGoalHours`). On a future day it reads "Logged ahead: 2h · 6h 30m to goal", the fill at half strength and no tick

**Future days (`lib/models/future_days.dart`)** — pure Dart, tested in
`test/future_days_test.dart`. `kMaxDaysAhead` (7) and `latestSelectableDate(now)`
are the one cap every date chooser uses: ›, the week strip and the picker here,
Log Time's chips and Pick, and Edit Time's picker (stretched to the entry's own
date when Harvest holds one further out). `isSelectableDay`, `isFutureDay`,
`isFutureSpentDate`, `daysFromToday` (UTC calendar days, so DST can't round a
day away) and `clampToSelectable` (a picker's `initialDate`) go with it.

- › walks one calendar day at a time up to the cap, into next week too: the
  provider always fetches the selected date's Monday–Sunday, so leaving the
  week refetches. A strip day past the cap is drawn fainter still, and is not tappable.
- Entries on a future day get a dashed `DurationPill(planned: true)` and a
  disabled ▶ ("Timers only run for today") in `TimeEntryCard`.
- **Log time for …** calls `HomeNavigation.maybeOf(context)?.logTimeFor(date)`:
  `HomeScreen` switches to Log Time and builds it with `initialDate`. Any
  ordinary tab change clears the handed-over date.
- The "new day" banner only shows when an *earlier* day is left selected
  overnight; a day ahead was chosen on purpose.
- **Insights stays at today**: › stops there, its picker opens on today, and a
  future day selected on Recent shows "This day hasn't happened yet" instead
  of analytics. Calendar import is untouched — it still logs only ended
  meetings.

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
- **Logged ahead** (`spentDate` after today): dashed pill, Continue disabled with "Timers only run for today".
- Pure helpers tested in `test/entry_display_test.dart`; the card in `test/time_entry_card_test.dart`.

**Tests** — `test/recent_entries_screen_test.dart` drives the screen behind a
`MockClient`: › into tomorrow (UPCOMING, Today jump, logged-ahead note, dashed
pill, footer), on to the cap where › disables and a strip day past it does
nothing, the next-week fetch, selecting a future day from the strip, and the
empty future day handing its date over.
