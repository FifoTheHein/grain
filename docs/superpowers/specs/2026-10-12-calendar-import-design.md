# Calendar (ICS) meeting import → Harvest

## Context
A Google Apps Script currently polls an Outlook published ICS feed and posts every finished meeting to Harvest. It logs everything to one hardcoded project/task (47666762 / Meetings), runs outside Grain, and keeps its own idempotency ledger. This moves that job into Grain:

- you set an ICS URL in Settings
- Grain logs finished meetings on its normal refresh
- the project/task for each meeting is chosen by rules, with an ADO work-item link and a default fallback

Decisions made with the user:
- **Flow:** auto-log on refresh. Meetings with no rule match and no default wait for review.
- **Mapping:** meeting rules over calendar fields (reusing the mapping-rule engine), then a work item # in the title resolved through the ADO mapping rules, then a default project/task.
- **Web:** browsers can't fetch the Outlook ICS because of CORS. Web gets an **Upload .ics** button instead. Android fetches the URL directly, and upload works there too.
- **Dedup:** a Harvest `external_reference` built from the ICS UID and start time, plus matching against entries the Apps Script already logged.


## Design

### 1. Pure model: `lib/models/calendar_event.dart` + `lib/models/ics_parser.dart` (no Flutter)
- `CalendarEvent { uid, summary, start (UTC), end (UTC), status, busyStatus, classification, organizerName, organizerEmail, attendees, categories, location, description, recurrenceId }`.
- `parseIcs(String text, {DateTime windowStart, DateTime windowEnd}) → List<CalendarEvent>`:
  - Unfolds lines the same way as the script's `parseICS`, and handles parameters (`DTSTART;TZID=…`) and escaped text (`\,` `\n`).
  - **Timezones:** builds offsets from the feed's own `VTIMEZONE` blocks: STANDARD/DAYLIGHT `TZOFFSETTO`, with yearly `RRULE` `BYMONTH`/`BYDAY` transitions. That fixes the script's known DST shortcut for W. Europe and Atlantic events. A small fixed table (the script's `TZID_UTC_OFFSET_HOURS`) is the fallback, then UTC for unknown or bare values, as the script does. All-day (`VALUE=DATE`) events are skipped.
  - **Recurrence:** expands `RRULE` for DAILY/WEEKLY/MONTHLY with `INTERVAL`, `BYDAY`, `UNTIL`, `COUNT` and `EXDATE`, clipped to the window. `RECURRENCE-ID` overrides replace their generated occurrence. Outlook published feeds ship series masters with RRULE, which the script never expanded. Implementation step 0 confirms this against the real feed.
- `meetingSkipReason(CalendarEvent, now) → String?` ports the script's filters:
  - CANCELLED
  - a `Declined:`/`Canceled:` prefix
  - busy status FREE or TRANSPARENT
  - PRIVATE/CONFIDENTIAL, or a summary of `Private Appointment`
  - not yet ended
  - shorter than 5 minutes or longer than 480 minutes

  It returns a reason rather than a bool, so the UI can explain why something was skipped.
- `meetingNotes(event)` strips the prefix and falls back to `(No title)`. `meetingKey(event)` builds the per-occurrence key `uid + start epoch`. `meetingExternalRefId(event)` returns `GrainCalendar_<fnv1a64(uid)>_<startEpochSec>`; Outlook UIDs are long, so they are hashed.
- `meetingMatchContext(event)` returns the map the rule engine consumes: `title`, `organizer`, `organizerEmail`, `attendees` (list), `attendeeDomains` (list), `categories` (list), `location`, `isTeams`.

### 2. Rule engine reuse (`lib/models/mapping_rule.dart`)
- The matcher is already generic over `context[field]`, and list values match on any element. No matcher changes.
- Add `abstract final class MeetingField` with constants, `all` and `labelFor`, mirroring `WorkItemField`.
- `MappingCondition.fromJson` currently falls back to `title` for an unknown field. That stays, and `title` exists in both field sets.
- `renderNoteTemplate`: also expand any `{key}` that is present in the context, keeping the existing aliases. That gives meetings `{title} {organizer} {location}`.
- `MeetingRuleProvider` (new, `lib/providers/meeting_rule_provider.dart`) uses the same CRUD and reorder as `MappingRuleProvider`, persisted to `meeting_rules_v1`. To avoid duplicating code, extract the list logic into a small shared base, or parameterize `MappingRuleProvider` by prefs key, whichever is the smaller diff.
- `lib/widgets/mapping_rule_editor.dart`: `MappingRuleList` / `showMappingRuleDialog` take a `fields` list + `labelFor` + provider. Today they hardcode `WorkItemField.all` at ~line 498.

### 3. Resolution order (per meeting)
1. The first enabled **meeting rule** match supplies project/task and an optional note template.
2. A **work item # in the title** (`#12345`, `AB#12345`). It is resolved via `AdoService.fetchWorkItem` on the default ADO instance, then attached as the ADO `ExternalReference`, exactly as Log Time does. If step 1 did not match, `MappingRuleProvider.matchIgnoringToggle(workItem)` picks project/task.
3. The **default meeting project/task** from Settings.
4. If none of these apply, the meeting is **pending** and is not logged.

The project/task must still be assigned to the user (from `AssignmentProvider`). If it isn't, the rule is skipped, as the existing mapping apply already does.

### 4. Service: `lib/services/calendar_service.dart`
- `CalendarService({http.Client? client})` uses the same injection pattern as `HarvestService`. `fetchIcs(url)` throws `CalendarFetchException` on a non-200 response.

### 5. Provider: `lib/providers/calendar_import_provider.dart`
- Settings in prefs:
  - `calendar_ics_url`
  - `calendar_auto_log` (bool)
  - `calendar_default_project_id` / `calendar_default_task_id`
  - `calendar_import_since`: set to "now" when auto-log is first enabled, so turning it on never back-fills months of meetings
  - `calendar_lookback_hours` (default 24)
  - the ledger `calendar_logged_v1` (key → spentDate, pruned after 30 days, as the script does)
- `sync({String? icsText})`:
  1. Get the feed: the fetched URL on Android, or uploaded text.
  2. Parse it for the window `max(importSince, now − lookback)` → now.
  3. Apply the skip filter.
  4. Fetch Harvest entries for the window with `HarvestService.fetchTimeEntries`. This is its own fetch, independent of Recent's selected week.
  5. Drop meetings that are already logged. A meeting counts as logged when any of these holds:
     - (a) its key is in the local ledger. This keeps an entry you deleted in Harvest from being recreated.
     - (b) an entry has a matching `externalReference.id`.
     - (c) a **fingerprint** matches: same `spent_date`, |hours − duration| ≤ 0.02, and notes containing the meeting title. This covers the Apps Script's existing entries, and ADO-linked meetings whose external ref slot holds the work item.
  6. Resolve the project/task (§3).
  7. Post through `TimeEntryProvider.submit(CreateTimeEntryRequest …)` so it reuses `_runMutation` and the existing automatic ADO Completed Work push on create. Send `started_time`/`ended_time` (local clock) only when `tracksByStartEnd` is true; otherwise send `hours` rounded to 2 dp.
  8. Write the ledger only after a confirmed success. A failure stays unlogged and is retried on the next sync.
- Exposes `pending` (needs a project), `lastSyncAt`, `lastResult {logged, skipped, pending, failed}` and `error`.
- **Trigger:** listens to `TimeEntryProvider` and runs `sync()` when `fetchedAt` advances, `autoLog` is on, a URL is set, and the platform is not web (`kIsWeb`). It is throttled to once per 5 minutes and guarded against re-entry. Wired in `main.dart` with the shared `HarvestService`, `TimeEntryProvider`, `AdoService`, `MappingRuleProvider`, `MeetingRuleProvider` and `AssignmentProvider`.
- `ExternalReference` (`lib/models/time_entry.dart`) gets optional `groupId`/`service`/`serviceIconUrl` constructor params. For a non-ADO meeting: `groupId: 'GrainCalendarEvent'`, `service: 'outlook.office365.com'`, and the permalink set to the Teams join URL if one is found in the description.

### 6. UI
- **Settings → "Calendar Import"** section (`_SectionHeader` pattern, after Quick Templates):
  - ICS URL field, obscured. On web, a note explains it only works on Android and to use Upload instead.
  - Auto-log switch, default project/task dropdowns (reusing the `_DefaultProjectDropdown`/`_DefaultTaskDropdown` pattern), and lookback.
  - **Sync now** (hidden on web), **Upload .ics** (all platforms, via a new `file_picker` dependency), and a last-sync status line.
  - A "Meeting Rules" sub-list using the parameterized `MappingRuleList` with `MeetingField`.
- **Pending meetings:** a small banner on `RecentEntriesScreen`, "N meetings need a project", opens `showPendingMeetingsSheet` (`lib/widgets/pending_meetings_sheet.dart`). It shows one row per meeting with project/task dropdowns plus **Log** / **Skip**. Skip writes the ledger.
- **Snackbar** after an auto-sync that logged anything: "Logged 3 meetings". Failures surface through the existing `TimeEntryProvider.error`.

### 7. Docs
- New `.claude/docs/calendar-import.md`, referenced from `CLAUDE.md`; also update the tests list in CLAUDE.md. Copy this design to `docs/superpowers/specs/2026-10-12-calendar-import-design.md`.

## Implementation order
0. **Spike, read-only:** fetch the real ICS once (with the user's OK) to confirm the RRULE masters, VTIMEZONE shape and Outlook busy-status fields. POST one test entry with the custom `external_reference` to confirm Harvest accepts a non-ADO `group_id`, then delete it. If Harvest rejects it, dedup falls back to ledger + fingerprint only, with no other design change.
1. Models + parser + tests (TDD).
2. Rule-engine generalization + editor parameterization (the existing mapping-rule tests must stay green).
3. Service + provider + tests with `MockClient`.
4. Settings UI, upload, pending sheet, banner.
5. Docs.

## Critical files
New: `lib/models/calendar_event.dart`, `lib/models/ics_parser.dart`, `lib/services/calendar_service.dart`, `lib/providers/calendar_import_provider.dart`, `lib/providers/meeting_rule_provider.dart`, `lib/widgets/pending_meetings_sheet.dart`, `test/ics_parser_test.dart`, `test/calendar_import_test.dart`, `.claude/docs/calendar-import.md`.
Modified: `lib/models/mapping_rule.dart`, `lib/widgets/mapping_rule_editor.dart`, `lib/models/time_entry.dart` (ExternalReference), `lib/screens/settings_screen.dart`, `lib/screens/recent_entries_screen.dart`, `lib/main.dart`, `pubspec.yaml` (`file_picker`), `CLAUDE.md`.

## Verification
- `flutter test`:
  - **Parser tests:** folding; UTC, TZID and bare times; DST transitions from VTIMEZONE; RRULE weekly/BYDAY/UNTIL/COUNT/EXDATE; a RECURRENCE-ID override.
  - **Filter tests:** each skip reason.
  - **Dedup tests:** ledger, external ref, and fingerprint against an Apps-Script-style entry.
  - **Resolution-order tests.**
  - **Provider tests** with `MockClient`: no `hours` when posting by start/end; a failed POST is not ledgered; a second sync posts nothing.
- `flutter analyze` clean.
- Manual: run Android against the real URL with auto-log on and `import_since` set to this morning, and confirm today's finished meetings appear once in Harvest with the right projects. Refresh again and nothing duplicates. Delete one in Harvest and it is not recreated. On web, upload an exported .ics and see the same result.
- Disable the Apps Script trigger only after the Android run checks out.

## Findings from the spike (2026-10-12)
- The real feed has 502 VEVENTs: 21 RRULE series masters and 320 RECURRENCE-ID overrides. Series occurrences without an override were never logged by the Apps Script. A dry run against the live feed found one on the first day: Monday's "Morning Check-in".
- There are three VTIMEZONEs. W. Europe and Atlantic define DST with yearly RRULEs. The "bare DTSTART" values the script worried about were the VTIMEZONE blocks' own lines, not events.
- The feed has **no ORGANIZER, ATTENDEE or CATEGORIES**, so meeting rules match on title, location, description, busy status and isTeams. The organizer field is kept for feeds that carry it.
- Harvest accepts a custom `external_reference` (`group_id: GrainCalendarEvent`) and derives `service` / icon from the permalink host. A Teams join link gets a Teams badge.
- The account tracks by duration (`started_time` null), so clock times are not sent.
- The feed returns no `Access-Control-Allow-Origin`, which confirms the web build cannot fetch it.
- `file_picker` is pinned to ^10.3 rather than the brand-new federated 13.x.
