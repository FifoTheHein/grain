# Timers

Start / stop / continue, backed by **Harvest's own timer** rather than a local
one. Harvest stays the single source of truth, so a timer started in Grain is
running in Harvest's web and mobile apps too, and vice versa.

This is the one place Grain deliberately diverges from HourGlass, which times
locally in SQLite and pushes hours to Harvest best-effort. Grain has no local
store and should not grow one for this.

**Service (`lib/services/harvest_service.dart`)**

- Starting is a create with **no `hours`** — `CreateTimeEntryRequest.hours` is
  nullable and `toJson` omits the key entirely, which Harvest reads as "start
  timing this now". Sending `0` would create a zero-length entry instead, so
  `test/timer_test.dart` pins the omission.
- `stopTimeEntry` → `PATCH /time_entries/{id}/stop`, rejected by Harvest when
  the entry is not running.
- `restartTimeEntry` → `PATCH /time_entries/{id}/restart`, rejected when it
  already is.

**Duration accounts** — none of this needs clock times. Harvest accrues
`hours` while the timer runs whether the account tracks by duration or by
start/end. `timer_started_at` marks the run in progress and is cleared on stop,
so it is not a source of history and does not give the Insights gap analysis
what it needs.

**Provider (`lib/providers/time_entry_provider.dart`)** — `startTimer`,
`stopTimer`, `restartTimer` run through the same `_runMutation` path as every
other write, and `runningEntry` finds the running one in the fetched week
(Harvest allows one per user). `fetchedAt` records when the visible entries
were read.

**The live counter** — `TimeEntry.liveHours(fetchedAt, now)` counts on from
`fetchedAt`, **not** from `timer_started_at`. Harvest's `hours` already
contains the run up to the moment of the response, so adding the whole run
again would double-count. `_LiveDurationPill` rebuilds once a second and only
for the running card.

**UI**

- `LogTimeScreen` — a "Start Timer" button under Log Time. It ignores the
  duration inputs, disables itself while another timer runs, and names the
  project holding it.
- `TimeEntryCard` — Stop on the running entry, Continue on any other. Continue
  is disabled while something else is running, since Harvest's one-timer rule
  means resuming would silently stop it.
- `EditTimeScreen` — reads the entry from the provider rather than trusting the
  snapshot it was pushed with, so it sees the timer state. While one runs the
  banner reads TIMER RUNNING, a `_RunningPanel` replaces the hours/minutes
  inputs with the live total and a Stop, and `UpdateTimeEntryRequest.hours` is
  left null so a save keeps whatever the timer has accrued. Project, task,
  notes, date and the ADO link stay editable throughout. Stopping from here
  refills the inputs with the settled total.

**ADO Completed Work is pushed explicitly, not automatically.** The automatic
paths can send a delta because they know what they already sent: create pushes
the full hours, edit pushes `newHours - entry.hours`, which create had already
sent. A timed entry has no such history — nothing was pushed when it started,
and hours accrued on Harvest's side — so an automatic push would have to
remember what it had sent to survive a Continue/Stop cycle or a mid-run
reload.

Rather than keep that bookkeeping, `showCompletedWorkSync`
(`lib/widgets/completed_work_sync.dart`) asks. It resolves the instance from
the entry's permalink, reads the current Completed Work, and confirms with the
before and after before writing. Two ways in: the **Sync to ADO** action on the
snackbar when a timer stops, and a button on Edit Time for any entry linked to
a work item — the recoverable path when the snackbar is gone.

Note that editing a timed entry does **not** fix it up: the delta is measured
from hours that were never pushed, so it sends only the difference.
