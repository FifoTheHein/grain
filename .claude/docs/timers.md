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

**Known gap** — ADO Completed Work is not synced when a timer stops. The
duration path syncs on submit and the edit path syncs the delta, but a timed
entry never passes through either. Editing the entry afterwards syncs it.
