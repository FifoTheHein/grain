# InsightsScreen (`lib/screens/insights_screen.dart`)

Day analytics for whichever date is selected on Recent — both screens read
`TimeEntryProvider.selectedDate` and `entries`, so navigating the date on one
moves the other. Stateless; no extra fetching.

**Model (`lib/models/day_insights.dart`)** — pure Dart, no Flutter, unit tested
in `test/day_insights_test.dart`. Works in minutes from midnight.

- `computeDayInsights({spans, windowStart, windowEnd, minGapMinutes,
  unplacedMinutes})` clamps spans to the work-day window, merges overlaps so
  double-logged time counts once, and returns `DayInsights { gaps,
  workedMinutes, unplacedMinutes, deadMinutes, windowMinutes, spanCount,
  contextSwitches, avgSessionMinutes, longestGapMinutes, placement }` plus
  `loggedMinutes` (placed + unplaced), `openMinutes` (window − placed) and
  `productivity` (logged ÷ window, capped at 1).
- `placement` is a `DayPlacement`: **none** (no spans), **partial** (spans
  plus `unplacedMinutes` logged by duration alone) or **full**. On a partial
  day the gaps are computed the same way but are *open* — the unplaced work
  sits somewhere in them — rather than dead.
- `gaps` holds only stretches ≥ `minGapMinutes`, each with its `previous` and
  `next` span (the one ending the overlap block before it, the one opening
  the block after it). `deadMinutes` comes from totals: window − placed
  (merged) − unplaced, floored at 0, so it holds without clock times; on a
  full day that is every uncovered minute, including sub-threshold ones.
- `contextSwitches` counts project/task changes between consecutive spans,
  only on a full day (with work unplaced the order isn't known) — HourGlass
  counted `spanCount - 1` instead, which conflates switching with simply
  logging twice.
- On today the caller passes `now` as `windowEnd`, so the part of the afternoon
  that has not happened yet is not counted as dead.
- `parseClockMinutes` reads Harvest's display times (`8:30am`, `8:30 AM`,
  `08:30`); `formatDuration` / `formatClock` render them back.

**Clock times** — gaps need to know *when* work happened, not just how long it
took. `TimeEntry` carries `startedTime` / `endedTime`, which Harvest only
populates when the account tracks time via start/end rather than duration;
`TimeEntry.span` turns a timed entry into an `InsightSpan` keyed by
`projectId:taskId` and returns null for untimed ones or an end at/before the
start.

**Meetings placed from the calendar** — a duration account has no clock
times, but an imported meeting's reference id
(`GrainCalendar_<hash>_<epoch>`) holds its series slot. `placedSpanOf`
(`lib/models/entry_display.dart`) is what Insights reads: an entry's `span`
when it has one, else for a meeting the slot (via `meetingStartFromRefId`, the
same decoding as Recent's `meetingStartLabel`, read as local time) for the
entry's hours, marked `fromCalendar`. A slot not on the entry's `spentDate`,
a span running past midnight, zero hours or a malformed id give null — the
entry counts by duration. Spans carry a `label` from `entryLabel` (first
notes line, work-item prefix stripped, else the task), which names the open
stretches. Timer entries are not guessed at from `updated_at`.

`TimeEntryProvider.tracksByStartEnd` learns which mode the account is in
from the fetched week, and `LogTimeScreen` only sends `started_time` /
`ended_time` (from Start & End mode) when it is true — a duration account never
receives fields it would ignore.

**Layout (top → bottom):** date nav row · `_StatTiles` (Logged, Coverage,
Unlogged/Over goal, and Switches on a full day) · `_TaskBreakdown` (per
project·task totals, largest first, bars in the `ProjectCategoryProvider`
colour) · then one of three, by `placement`:

- **full** — "Gaps of 15m or more", the brand-filled timeline ("covered ·
  dead") and the gap list. Meetings placed from the calendar are merged in
  with the timed entries.
- **partial** (`_partialDay`) — "The day" with "Xh placed from your
  calendar"; `_PlacedTimeline`, placed spans in project colours over a
  hatched (`_HatchPainter`) background. A block carries its title (ellipsis
  when long) once it is 48 px wide or the whole title fits. Hour ticks run
  hourly, two-hourly past six hours, each kept only where its measured label
  clears the end labels and the tick before it. The legend has one swatch per
  project on the timeline, named by the part after the last `|` ("CRT
  Team"), then "Open: other work or nothing"; `_UnplacedCard`, a
  dashed card saying how much was logged by duration and how much of the work
  day that leaves unlogged (the Unlogged tile's figure, goal − logged), with a
  chip per unplaced entry (`entryLabel` · duration, largest first); and
  "Open between meetings" ("15m or more · longest X"), one `_OpenRow` per gap:
  "after <previous span>", or "before <first span>" for a stretch opening the
  day. The Unlogged tile reads "from totals, no clock times needed".
- **none** — the `_EmptyCard` explaining why gaps are unavailable.

A future day shows "This day hasn't happened yet" instead of all of this.

**Tests** — `test/day_insights_test.dart` (the model, `placedSpanOf`, partial
days) and `test/insights_screen_test.dart` (the screen behind a `MockClient`
in each of the three states).

**Settings** — the gap threshold lives in the Work Day section as "Report gaps
of at least" (`ProjectCategoryProvider.minGapMinutes`, `min_gap_minutes` in
prefs, default 15).
