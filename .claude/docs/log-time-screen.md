# LogTimeScreen (`lib/screens/log_time_screen.dart`)

Creates entries. The form scrolls; the action bar does not.

**Layout (top → bottom):** quick templates · mapping-rule banner · project/task
· date chips · Duration / Start & End toggle · the stepper (or the two clock
boxes) · notes, with the detected-work-item card under them · the ADO section.
Pinned below the scroll area, above the bottom nav (or at the foot of the wide
layout's content column): `LogActionBar`.

**Duration (`DurationStepper`, `lib/widgets/duration_stepper.dart`)** — a
controlled widget (`minutes` in, `onChanged` out) so Edit Time can adopt it
without restructuring.

- `− [1h 45m] +`, decimal hours underneath, and "tap ±1 min · hold 1 → 5 →
  15" under that. A tap moves 1 minute. Holding repeats (`HoldToRepeat`, a
  `Listener` on raw pointer events, so the first step lands on press) and
  speeds up on `holdStepMinutes`: 1-minute steps, then 5 from 1.5 s, then 15
  from 4 s, each snapping onto its own grid (1h 23m → 1h 25m under a 5). The
  schedule is counted in ticks (`holdElapsedAtTick`), not read from a clock,
  so the widget test replays it exactly. − is disabled at 0, + at 24h.
- Quick chips 15m · 30m · 45m · 1h · 1½h · 2h set the value and are selected
  while it matches.
- Tapping the number swaps in a text field with a live "= 1h 45m" read-back.
  Enter or leaving the field commits; Escape cancels; anything unreadable
  leaves the value alone.

**Parsing (`lib/models/duration_input.dart`)** — pure Dart, tested in
`test/duration_input_test.dart` (the acceleration schedule too). `parseDurationInput` takes `1:45`, `1.75`,
`1,75`, `1h45`, `1h 45m`, `1.5h`, `2 hrs`, `105m`, `45 min` and bare numbers.
**A bare whole number is minutes** (`90` → 1h 30m, `2` → 2m); a decimal is
hours (`2.0` → 2h). Over 24h is rejected. Also `formatDurationLabel`,
`formatDecimalHours`, `formatQuickDuration` and `stepDuration`.

**No default duration.** The stepper opens at 0 and returns to 0 after a log;
the old 1h default got logged whenever someone forgot to change it. "Duration
must be greater than 0" only appears after a tap on the disabled Log button.

**Suggestions (`lib/models/log_time_defaults.dart`)** — pure Dart over a day's
`TimeEntry`s via `TimeEntry.span`, tested in `test/log_time_defaults_test.dart`.
The screen reads the day from `TimeEntryProvider.entriesOn(date)`, which
filters `weekEntries` (the whole fetched week) because Log Time's date is its
own, not Recent's. A day outside that week reads as empty.

- `suggestGap` — the gap chip, "1h 20m unlogged since Standup ended at 10:40"
  with **Use**. From the end of today's latest-*ending* timed entry to now.
  Hidden when nothing today carries clock times, a timer is running, the gap
  is under 5 minutes, the date is not today, in Start & End mode, or once the
  stepper already holds that value. The label is the entry's first notes line
  (work-item prefix stripped by `workItemNotesLine`), else its task.
- `startEndDefaults` — Start is the end of the day's last timed entry. With
  none, the work-day start from `ProjectCategoryProvider` **plus whatever the
  day has logged by duration** (so a duration-tracking account still starts
  "after what you've done"; an empty day is just the work-day start). End is
  now on today, start + 1h otherwise. On today a start at or past now is
  pulled back to an hour before now.

**Start & End** — the times follow the defaults (and so keep up with "now"
and with entries that arrive later) until touched; a nudge or a pick pins
both. Each box is `−1 · HH:MM · +1` (`nudgeClock`), the nudges holding to
repeat on the same 1 → 5 → 15 schedule as the stepper; tapping the time opens
the 24h picker, and End can't nudge past now on today. A caption says where the
default came from ("after Standup", "work day start", "now"). "= 1h 20m"
shows live underneath, replaced by "End time must be after start time" when it
is. Clock times are still only sent when `tracksByStartEnd`.

**Action bar (`LogActionBar`, `lib/widgets/log_action_bar.dart`)** — stateless.
"Log 1h 45m" over "NWR001 · Development · today" (yesterday / `EEE d MMM`), or
the `HH:MM–HH:MM` range in Start & End (prefixed with the date off today).
Disabled with a reason in place of the subline: "Pick a project and task",
"End must be after start", "Set a duration first". `onDisabledTap` lets the
screen show the zero-duration error. The ▶ beside it starts a timer: disabled
while one runs, tooltip naming the project holding it.

**Tidy-ups**

- Date: Yesterday / Today / Tomorrow / Pick (an icon chip, `showDatePicker`
  up to `latestSelectableDate`, today + 7) chips, the date at the right.
  Changing it resets Start & End to the new day's defaults. `initialDate`
  opens the screen on another day — Recent's empty future day hands one over
  through `HomeNavigation`.
- **Logging ahead** (a date after today): an "UPCOMING · Logging ahead.
  Timers only run for today." line under the chips, no gap chip, and the ▶
  disabled with that tooltip. Start & End default as on any other day that
  isn't today — after what the day already holds, so the work-day start to an
  hour later on an empty one. Harvest takes a future `spent_date` as-is; the
  create path needs nothing special.
- The Duration / Start & End choice persists in `log_time_start_end`.
- A `#123` or `AB#123` in the notes (`workItemIdFromTitle` from `meeting.dart`)
  while nothing is linked shows a card: the item's title when cached (fetched
  from the selected instance, else the first with a PAT, else the first),
  **Link** (ticks the ADO box, picks that instance, fills the id and runs the
  normal preview + mapping-rule path) and a dismiss.
- The ADO instance `SegmentedButton` only appears with two or more instances;
  ticking the box with one selects it.

Unchanged: quick templates, the mapping-rule banner and Undo, the work item
picker and preview, the Completed Work push. Edit Time still uses its own
hours/minutes inputs.

**Tests** — `test/duration_stepper_test.dart` (stepper and action bar),
`test/log_time_screen_test.dart` (the screen behind a `MockClient`: disabled
bar and error, chips, date word, Start & End persistence and nudges, Tomorrow
and its disabled timer, Start & End on a future day, `initialDate`, the Link
card with a single instance).
