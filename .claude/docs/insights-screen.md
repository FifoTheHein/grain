# InsightsScreen (`lib/screens/insights_screen.dart`)

Day analytics for whichever date is selected on Recent — both screens read
`TimeEntryProvider.selectedDate` and `entries`, so navigating the date on one
moves the other. Stateless; no extra fetching.

**Model (`lib/models/day_insights.dart`)** — pure Dart, no Flutter, unit tested
in `test/day_insights_test.dart`. Works in minutes from midnight.

- `computeDayInsights({spans, windowStart, windowEnd, minGapMinutes})` clamps
  spans to the work-day window, merges overlaps so double-logged time counts
  once, and returns `DayInsights { gaps, workedMinutes, deadMinutes,
  windowMinutes, spanCount, contextSwitches, avgSessionMinutes,
  longestGapMinutes }` plus a `productivity` getter (worked ÷ window).
- `gaps` holds only stretches ≥ `minGapMinutes`; `deadMinutes` counts every
  uncovered minute including sub-threshold ones.
- `contextSwitches` counts project/task changes between consecutive spans —
  HourGlass counted `spanCount - 1` instead, which conflates switching with
  simply logging twice.
- On today the caller passes `now` as `windowEnd`, so the part of the afternoon
  that has not happened yet is not counted as dead.
- `parseClockMinutes` reads Harvest's display times (`8:30am`, `8:30 AM`,
  `08:30`); `formatDuration` / `formatClock` render them back.

**Clock times** — gaps need to know *when* work happened, not just how long it
took. `TimeEntry` carries `startedTime` / `endedTime`, which Harvest only
populates when the account tracks time via start/end rather than duration;
`TimeEntry.span` turns a timed entry into an `InsightSpan` keyed by
`projectId:taskId` and returns null for untimed ones or an end at/before the
start. `TimeEntryProvider.tracksByStartEnd` learns which mode the account is in
from the fetched week, and `LogTimeScreen` only sends `started_time` /
`ended_time` (from Start & End mode) when it is true — a duration account never
receives fields it would ignore.

**Layout (top → bottom):** date nav row · `_StatTiles` (Logged, Coverage,
Unlogged/Over goal, and Switches when timed) · `_TaskBreakdown` (per
project·task totals, largest first, bars in the `ProjectCategoryProvider`
colour) · timeline + gap list, or an `_EmptyCard` explaining why gaps are
unavailable when no entry carries clock times.

**Settings** — the gap threshold lives in the Work Day section as "Report gaps
of at least" (`ProjectCategoryProvider.minGapMinutes`, `min_gap_minutes` in
prefs, default 15).
