import 'package:intl/intl.dart';

import '../config/app_config.dart';
import '../models/calendar_event.dart';
import '../models/meeting.dart';
import '../models/time_entry.dart';
import 'harvest_service.dart';

/// Everything needed to log one meeting, once its project/task is known.
class MeetingPlan {
  final MeetingTarget target;
  final String notes;
  final ExternalReference externalReference;

  /// Runs after the entry is created — the ADO Completed Work push for a
  /// meeting linked to a work item. A failure here does not undo the entry.
  final Future<void> Function(double hours)? afterLogged;

  const MeetingPlan({
    required this.target,
    required this.notes,
    required this.externalReference,
    this.afterLogged,
  });
}

/// Picks the project/task and note for a meeting, or null to leave it pending.
typedef MeetingResolver = Future<MeetingPlan?> Function(CalendarEvent event);

class MeetingFailure {
  final CalendarEvent event;
  final String message;
  const MeetingFailure(this.event, this.message);
}

class MeetingImportResult {
  final List<CalendarEvent> logged;
  final int alreadyLogged;
  final Map<MeetingSkip, int> skipped;

  /// Meetings no rule or default could place. Not logged, waiting for review.
  final List<CalendarEvent> pending;
  final List<MeetingFailure> failed;

  const MeetingImportResult({
    this.logged = const [],
    this.alreadyLogged = 0,
    this.skipped = const {},
    this.pending = const [],
    this.failed = const [],
  });
}

/// The meeting import itself, independent of Flutter and storage so it can be
/// driven with a mock HTTP client: filter, de-duplicate against Harvest, place
/// each meeting, and post it.
class MeetingImporter {
  final HarvestService harvest;
  final MeetingResolver resolve;

  MeetingImporter({required this.harvest, required this.resolve});

  /// Imports [events] that ended inside [windowStart, now].
  ///
  /// [ledger] holds keys of meetings already handled here; [markLogged] is
  /// called only after Harvest confirms a create, so a failed post is retried
  /// on the next run rather than lost.
  Future<MeetingImportResult> run({
    required List<CalendarEvent> events,
    required DateTime windowStart,
    required DateTime now,
    required Set<String> ledger,
    required bool tracksByStartEnd,
    required Future<void> Function(CalendarEvent event) markLogged,
  }) async {
    final skipped = <MeetingSkip, int>{};
    final candidates = <CalendarEvent>[];
    for (final e in events) {
      if (e.end.isBefore(windowStart)) continue;
      final reason = meetingSkipReason(e, now);
      if (reason != null) {
        // Unfinished meetings are simply not due yet, not skipped.
        if (reason != MeetingSkip.notEnded) {
          skipped[reason] = (skipped[reason] ?? 0) + 1;
        }
        continue;
      }
      candidates.add(e);
    }
    if (candidates.isEmpty) return MeetingImportResult(skipped: skipped);

    final fmt = DateFormat('yyyy-MM-dd');
    final entries = await harvest.fetchTimeEntries(
      from: fmt.format(windowStart.toLocal()),
      to: fmt.format(now.toLocal()),
    );

    final logged = <CalendarEvent>[];
    final pending = <CalendarEvent>[];
    final failed = <MeetingFailure>[];
    var alreadyLogged = 0;

    for (final e in candidates) {
      if (isMeetingLogged(e, ledger: ledger, entries: entries)) {
        alreadyLogged++;
        continue;
      }
      final plan = await resolve(e);
      if (plan == null) {
        pending.add(e);
        continue;
      }
      final error = await logOne(e, plan,
          tracksByStartEnd: tracksByStartEnd, markLogged: markLogged);
      if (error == null) {
        logged.add(e);
      } else {
        failed.add(MeetingFailure(e, error));
      }
    }

    return MeetingImportResult(
      logged: logged,
      alreadyLogged: alreadyLogged,
      skipped: skipped,
      pending: pending,
      failed: failed,
    );
  }

  /// Posts one meeting. Returns null on success or the error message.
  Future<String?> logOne(
    CalendarEvent e,
    MeetingPlan plan, {
    required bool tracksByStartEnd,
    required Future<void> Function(CalendarEvent event) markLogged,
  }) async {
    final hours = meetingHours(e);
    final request = CreateTimeEntryRequest(
      userId: AppConfig.userId,
      projectId: plan.target.projectId,
      taskId: plan.target.taskId,
      spentDate: meetingSpentDate(e),
      // A start/end account derives hours from the clock times; sending both
      // is harmless, and a duration account ignores the times entirely, so
      // they are only sent where they mean something.
      hours: hours,
      notes: plan.notes,
      externalReference: plan.externalReference,
      startedTime: tracksByStartEnd ? meetingClock(e.start) : null,
      endedTime: tracksByStartEnd ? meetingClock(e.end) : null,
    );
    try {
      await harvest.createTimeEntry(request);
    } on HarvestApiException catch (ex) {
      return '${ex.statusCode}: ${ex.message}';
    } catch (ex) {
      return ex.toString();
    }
    await markLogged(e);
    try {
      await plan.afterLogged?.call(hours);
    } catch (_) {
      // The entry exists; a Completed Work push can be redone from Edit Time.
    }
    return null;
  }
}

/// The external reference a meeting entry carries when it is not linked to a
/// work item. Harvest derives the service and icon from the permalink host, so
/// the Teams join link gives the entry a Teams badge.
ExternalReference meetingReference(CalendarEvent e) {
  final permalink = teamsJoinUrl(e) ?? 'https://outlook.office.com/calendar/';
  final host = Uri.parse(permalink).host;
  return ExternalReference(
    id: meetingExternalRefId(e),
    groupId: 'GrainCalendarEvent',
    permalink: permalink,
    service: host,
    serviceIconUrl:
        'https://proxy.harvestfiles.com/production_harvestapp_public/uploads/platform_icons/$host.png',
  );
}
