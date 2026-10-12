# Calendar Import

Logs finished meetings from a published ICS calendar (Outlook → Shared
calendars → Publish) to Harvest. It replaces a Google Apps Script that posted
every meeting to one hardcoded project. Here each meeting is placed by rules,
and recurring series are actually expanded. The script never expanded them,
so any occurrence without an override was silently missed.

**Web vs Android.** Outlook's published feed sends no CORS headers, so a
browser cannot read it. `CalendarImportProvider.canFetchUrl` is `!kIsWeb`.
Android fetches the URL and auto-logs. Web offers **Upload .ics**, which runs
the same pipeline on the file (it works on Android too).

**Parser (`lib/models/ics_parser.dart`)** is pure Dart, unit tested in
`test/ics_parser_test.dart`. `parseIcs(text, windowStart, windowEnd)` returns
`CalendarEvent`s (`lib/models/calendar_event.dart`) overlapping the window,
with series expanded.

- **Time zones** come from the feed's own `VTIMEZONE` blocks, including yearly
  DST transitions. A small Windows-name table is the fallback, and unknown or
  bare times are read as UTC.
- **`RRULE`** supports DAILY / WEEKLY (`BYDAY`, `INTERVAL`, `WKST`) / MONTHLY
  (`BYMONTHDAY`, ordinal `BYDAY`) / YEARLY, with `UNTIL`, `COUNT` and `EXDATE`.
  Expansion runs in wall time, so a series keeps its local time across DST.
- **`RECURRENCE-ID` overrides** replace their generated occurrence. Outlook's
  feed carries ~20 series masters and hundreds of overrides.
- **`CalendarEvent.occurrence`** is the slot in the series: the generated
  start, or the `RECURRENCE-ID`. It doesn't move when a meeting is
  rescheduled, which is what keeps the dedup keys stable.
- Parsing a 3 MB feed takes ~1 s, so the provider runs it through `compute`.

**Meeting rules model (`lib/models/meeting.dart`)** is unit tested in
`test/meeting_test.dart`.

- **`meetingSkipReason`** ports the script's filters: cancelled (status or a
  `Canceled:` prefix), declined (`Declined:` prefix), free/transparent,
  private (or the redacted "Private Appointment"), not yet ended, or shorter
  than 5 / longer than 480 minutes. Tentative and out-of-office still log, as
  before.
- **`meetingMatchContext`** is what meeting rules match on (`MeetingField`):
  title, location, description, organizer, busy status, and isTeams
  (`yes`/`no`). Outlook's published feed strips organizer and attendees, so
  rules there mostly work on title and location.
- **`isMeetingLogged`** checks three ways:
  - **the local ledger**, which also stops a meeting deleted in Harvest from
    being recreated;
  - **an entry carrying `meetingExternalRefId`** (`GrainCalendar_<hash>_<epoch>`);
  - **a fingerprint**: same date, hours within 0.02, and notes containing the
    title. This catches the Apps Script's entries, and meetings linked to a
    work item, whose reference slot holds the work item.
- **`chooseMeetingTarget`** picks, in order:
  1. the first meeting rule;
  2. the work item rule for a `#123` / `AB#123` in the title;
  3. the default project/task.

  It passes over unassigned targets. If nothing applies, the meeting is
  pending.

**Importer (`lib/services/meeting_importer.dart`)** is Flutter-free and tested
with a `MockClient` in `test/calendar_import_test.dart`.

- **One run:** filter, fetch Harvest entries for the window, drop meetings
  already logged, resolve, then post.
- **The ledger** is written only after Harvest confirms the create. A failed
  post retries on the next run.
- **Clock times** (`started_time` / `ended_time`) are sent only when
  `tracksByStartEnd` is true.
- **`meetingReference`** uses the Teams join link as the permalink. Harvest
  derives the service from that host and shows a Teams badge; this was
  verified against the live API.

**Provider (`lib/providers/calendar_import_provider.dart`)**

- **Settings in prefs:** `calendar_ics_url`, `calendar_auto_log`,
  `calendar_default_project_id` / `_task_id`, `calendar_lookback_hours`
  (default 24) and `calendar_ado_instance` (the instance `#123` in titles is
  looked up in; defaults to the first with a PAT).
- **The ledger** is `calendar_logged_v1` (key → spent date), pruned after 30
  days.
- **`calendar_import_since`** is set to "now" when auto-log is first turned
  on, so enabling it never back-fills history. Settings offers "From start of
  today". An upload ignores it and uses only the lookback.
- **The trigger:** it listens to `TimeEntryProvider` and syncs when
  `fetchedAt` advances, at most every 5 minutes. It also syncs once after its
  own settings load at startup.
- **Work-item meetings** reuse `AdoService.workItemReference`, the same
  reference and note prefix as Log Time. After logging, they push Completed
  Work when `ado_update_completed_work` is on.
- **`logPending` / `skipPending`** back the review sheet.

**UI**

- **Settings → Calendar Import** is `CalendarImportSettings`
  (`lib/widgets/calendar_import_settings.dart`):
  - the URL, the auto-log switch and the "since" line;
  - the default project/task, the lookback and the ADO instance;
  - Sync now / Upload .ics and the last-sync summary (`describeImport`);
  - the meeting rule list: `MappingRuleList(kind: RuleKind.meeting)`. The rule
    editor is shared, and `RuleKind` carries the field set, wording and
    provider. `MeetingRuleProvider` is a `MappingRuleProvider` on
    `meeting_rules_v1`.
- **Recent** shows "N meetings need a project" while anything is pending. It
  opens `showPendingMeetingsSheet` (`lib/widgets/pending_meetings_sheet.dart`),
  which has a project/task picker plus Log / Skip per meeting.
