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
- `longestFocusWindow(insights)` is the longest gap (ties to the earlier),
  null with nothing placed. Gaps are already ≥ `minGapMinutes`, and so is the
  window. On a partial day it is time without meetings, not without work.
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

**Breakdowns (`lib/models/day_breakdown.dart`)** — pure Dart, tested in
`test/day_breakdown_test.dart`.

- `meetingLoad(entries)` — minutes, count and `percentOfLogged` of the
  entries `isImportedMeeting` (reference id starting `kMeetingRefPrefix`),
  placed or not. A meeting linked to a work item carries the work item's
  reference instead, so it counts as work: nothing on it says meeting.
- `groupByWorkItem(entries)` — one `WorkItemGroup` per `adoReference`, keyed
  by the work item number plus the permalink host (so the composite and bare
  id shapes merge, and #123 on two organisations doesn't), largest first,
  then a "No work item" group for everything else (left out when empty).
  Each carries its `permalink` and a `notesTitle` from `workItemNotesLine`.

**Log this (`lib/models/log_time_prefill.dart`)** — pure Dart, tested in
`test/log_time_prefill_test.dart`. `prefillForSlot` turns a gap into a
`LogTimePrefill` for Log Time:

- **Start/end account** (`tracksByStartEnd`) — Start & End with the slot's own
  times, captioned "after <previous>" / "before <next>".
- **Duration account** — Duration, `min(slot, unlogged)` where unlogged is the
  Unlogged tile's goal − logged. Harvest ignores clock times there, and part
  of the slot is already covered by work logged by duration, so logging the
  whole slot would count that time twice. With nothing unlogged it returns
  null and the button is disabled, the reason in its tooltip.

The button sits on every "Open between meetings" row and every gap row on a
full day, and calls `HomeNavigation.logTimeFor(date, prefill: …)`. See
`log-time-screen.md` for what Log Time does with it.

**Layout (top → bottom):** date nav row · `_PendingMeetingsBanner` · `_StatTiles`
(Logged, Coverage, Unlogged/Over goal, Meetings when there are any, and
Switches on a full day; one row when each tile gets 120 px, else three across,
two on a phone) · `_WhereItWent` · then one of three, by `placement`:

- **full** — "Gaps of 15m or more", the brand-filled timeline ("covered ·
  dead") and the gap list. Meetings placed from the calendar are merged in
  with the timed entries. The longest gap is outlined (`focus-window`) and
  read out: "Longest focus window: 11:30 – 17:00 · 5h 30m with nothing
  logged".
- **partial** (`_partialDay`) — "The day" with "Xh placed from your
  calendar"; `_PlacedTimeline`, placed spans in project colours over a
  hatched (`_HatchPainter`) background. A block carries its title (ellipsis
  when long) once it is 48 px wide or the whole title fits. Hour ticks run
  hourly, two-hourly past six hours, each kept only where its measured label
  clears the end labels and the tick before it. The legend has one swatch per
  project on the timeline, named by the part after the last `|` ("CRT
  Team"), then "Open: other work or nothing", then the focus line ("… with no meetings",
  or "with nothing placed" when not everything placed is a meeting), the
  window outlined on the timeline in success green; `_UnplacedCard`, a
  dashed card saying how much was logged by duration and how much of the work
  day that leaves unlogged (the Unlogged tile's figure, goal − logged), with a
  chip per unplaced entry (`entryLabel` · duration, largest first); and
  "Open between meetings" ("15m or more · longest X"), one `_OpenRow` per gap:
  "after <previous span>", or "before <first span>" for a stretch opening the
  day. The Unlogged tile reads "from totals, no clock times needed".
- **none** — the `_EmptyCard` explaining why gaps are unavailable.

A future day shows "This day hasn't happened yet" instead of all of this.

**Where it went** — a Project · task / Work item switch, remembered in
`insights_breakdown_by_work_item`. Project · task is `_TaskBreakdown` (bars
in the project colour); Work item is `_WorkItemBreakdown`: `#id`, the title
from the `AdoService` cache (instance found by `matchesPermalink`) else the
notes title else "Work item #id", the entry count and total, the left border
and id in `workItemStateColor` (shared with `WorkItemChip`) when the item is
cached. Insights reads the cache only; Recent's prefetch fills it.

**Unlogged meetings** — `_PendingMeetingsBanner`: "2 meetings from yesterday
aren't logged · Sprint retro and Vendor sync need a project", **Review**
opening `showPendingMeetingsSheet`. It reads `CalendarImportProvider.pending`
for the selected date (`meetingSpentDate`), so it is hidden with none, on a
future day, and on the web until an upload has run. Only pending meetings: the
ledger (`calendar_logged_v1`, key → spent date) is written the same way for a
meeting logged and one skipped from the sheet, and holds no title, so skipped
meetings can't be named.

**Tests** — `test/day_insights_test.dart` (the model, `placedSpanOf`, partial
days, the focus window), `test/day_breakdown_test.dart`,
`test/log_time_prefill_test.dart` and `test/insights_screen_test.dart` (the
screen behind a `MockClient` in each of the three states; Log this handing
over a capped duration, disabled at goal, and a full day's start/end; the
Meetings tile and focus line; the work item switch and its memory; the banner,
fed by a real upload, opening the sheet).

**Settings** — the gap threshold lives in the Work Day section as "Report gaps
of at least" (`ProjectCategoryProvider.minGapMinutes`, `min_gap_minutes` in
prefs, default 15).
