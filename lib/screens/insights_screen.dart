import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ado_work_item.dart';
import '../models/calendar_event.dart';
import '../models/day_breakdown.dart';
import '../models/day_insights.dart';
import '../models/entry_display.dart';
import '../models/future_days.dart';
import '../models/log_time_prefill.dart';
import '../models/meeting.dart' show meetingSpentDate;
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/calendar_import_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../theme/harvest_palette.dart';
import '../theme/harvest_tokens.dart';
import '../widgets/dashed_border.dart';
import '../widgets/error_banner.dart';
import '../widgets/pending_meetings_sheet.dart';
import '../widgets/work_item_chip.dart' show workItemStateColor;
import 'home_screen.dart';

/// SharedPreferences key remembering whether "Where it went" groups by work
/// item (true) or by project and task (false).
const kInsightsByWorkItemKey = 'insights_breakdown_by_work_item';

/// Day analytics for the date selected on the Recent screen: how much of the
/// work day is accounted for, where it went, and — when the Harvest account
/// records clock times — where the gaps are.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  static int _minutesOf(TimeOfDay t) => t.hour * 60 + t.minute;

  void _shiftDate(BuildContext context, int days) {
    final provider = context.read<TimeEntryProvider>();
    final newDate = provider.selectedDate.add(Duration(days: days));
    if (!newDate.isAfter(DateTime.now())) {
      provider.loadRecentEntries(date: newDate);
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final provider = context.read<TimeEntryProvider>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      // Recent can leave a future day selected; Insights stops at today.
      initialDate:
          isFutureDay(provider.selectedDate, now) ? now : provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) provider.loadRecentEntries(date: picked);
  }

  /// A day where some entries are placed (imported meetings, usually) and the
  /// rest were logged by duration: the placed ones on a timeline, the rest
  /// counted in a card, and the stretches between them listed as open — the
  /// unplaced work is somewhere in them, so they are not dead.
  List<Widget> _partialDay(
    BuildContext context, {
    required DayInsights insights,
    required List<InsightSpan> spans,
    required List<TimeEntry> unplaced,
    required Map<int, String> projectNames,
    required int unloggedMinutes,
    required int windowStart,
    required int windowEnd,
    required int minGapMinutes,
    required InsightGap? focus,
    required Widget Function(InsightGap gap) openRow,
  }) {
    final palette = HarvestTokens.of(context);
    final heading = TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: palette.text2);
    final note = TextStyle(fontSize: 11, color: palette.text3);
    final allCalendar = spans.every((s) => s.fromCalendar);

    return [
      Row(
        children: [
          Expanded(child: Text('The day', style: heading)),
          Text(
            '${formatDuration(insights.workedMinutes)} placed'
            '${allCalendar ? ' from your calendar' : ''}',
            style: note,
          ),
        ],
      ),
      const SizedBox(height: 8),
      _PlacedTimeline(
        spans: spans,
        windowStart: windowStart,
        windowEnd: windowEnd,
        projectNames: projectNames,
        focus: focus,
      ),
      if (focus != null) ...[
        const SizedBox(height: 8),
        _FocusLine(
          gap: focus,
          without: allCalendar ? 'with no meetings' : 'with nothing placed',
        ),
      ],
      const SizedBox(height: 14),
      _UnplacedCard(
        entries: unplaced,
        unplacedMinutes: insights.unplacedMinutes,
        unloggedMinutes: unloggedMinutes,
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
                allCalendar ? 'Open between meetings' : 'Open between entries',
                style: heading),
          ),
          Text(
            '${minGapMinutes}m or more'
            '${insights.longestGapMinutes > 0 ? ' · longest ${formatDuration(insights.longestGapMinutes)}' : ''}',
            style: note,
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (insights.gaps.isEmpty)
        const _EmptyCard(
          icon: Icons.check_circle_outline,
          title: 'No open stretches',
          message: 'What’s placed fills the work day, with nothing longer '
              'than the gap threshold in between.',
        )
      else
        for (final gap in insights.gaps) openRow(gap),
    ];
  }

  /// "Log this" for an open stretch: the Log Time form it would open, or the
  /// reason it can't.
  ({LogTimePrefill? prefill, String tooltip}) _logThis(
    InsightGap gap, {
    required DateTime date,
    required bool tracksByStartEnd,
    required int unloggedMinutes,
  }) {
    final prefill = prefillForSlot(
      date: date,
      gap: gap,
      tracksByStartEnd: tracksByStartEnd,
      unloggedMinutes: unloggedMinutes,
    );
    if (prefill == null) {
      return (
        prefill: null,
        tooltip: 'Nothing left to log: the day’s goal is already covered '
            'by what was logged',
      );
    }
    return (
      prefill: prefill,
      tooltip: prefill.startEnd
          ? 'Log ${formatClock(prefill.start)}–${formatClock(prefill.end)}'
          : 'Log ${formatDuration(prefill.minutes)}'
              '${prefill.minutes < gap.minutes ? ', what’s left unlogged' : ''}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final entryProvider = context.watch<TimeEntryProvider>();
    final settings = context.watch<ProjectCategoryProvider>();

    final entries = entryProvider.entries;
    final isToday = entryProvider.isSelectedDateToday;
    // Recent can select up to a week ahead; Insights only reads what has
    // happened, so a future day gets a pointer back rather than analytics.
    final isFuture = isFutureDay(entryProvider.selectedDate, DateTime.now());

    // Entries with a time of day — clock times, or an imported meeting's
    // calendar slot — drive the timeline; the rest still count towards the
    // day's total, by duration.
    final spans = <InsightSpan>[];
    final unplaced = <TimeEntry>[];
    for (final e in entries) {
      final s = placedSpanOf(e);
      s == null ? unplaced.add(e) : spans.add(s);
    }
    final unplacedMinutes =
        unplaced.fold<double>(0, (sum, e) => sum + e.hours * 60).round();
    final loggedMinutes =
        entries.fold<double>(0, (sum, e) => sum + e.hours * 60).round();

    final windowStart = _minutesOf(settings.workDayStart);
    final windowEndSetting = _minutesOf(settings.workDayEnd);
    // On today, stop the window at now so the afternoon that has not happened
    // yet is not counted as dead time.
    final now = TimeOfDay.now();
    final windowEnd = isToday
        ? _minutesOf(now).clamp(windowStart, windowEndSetting)
        : windowEndSetting;

    final insights = computeDayInsights(
      spans: spans,
      windowStart: windowStart,
      windowEnd: windowEnd,
      minGapMinutes: settings.minGapMinutes,
      unplacedMinutes: unplacedMinutes,
    );
    final partial = insights.placement == DayPlacement.partial;

    final goalMinutes = (settings.dailyGoalHours * 60).round();
    final unloggedMinutes = goalMinutes - loggedMinutes;
    final coverage =
        goalMinutes > 0 ? (loggedMinutes / goalMinutes).clamp(0.0, 1.0) : 0.0;
    final focus = longestFocusWindow(insights);

    // Meetings the calendar import couldn't place, on this day.
    final selectedDay =
        DateFormat('yyyy-MM-dd').format(entryProvider.selectedDate);
    final pendingOnDay = context
        .watch<CalendarImportProvider>()
        .pending
        .where((e) => meetingSpentDate(e) == selectedDay)
        .toList();

    Widget slotRow(InsightGap gap, {required bool open}) {
      final action = _logThis(
        gap,
        date: entryProvider.selectedDate,
        tracksByStartEnd: entryProvider.tracksByStartEnd,
        unloggedMinutes: unloggedMinutes,
      );
      final prefill = action.prefill;
      final onLogThis = prefill == null
          ? null
          : () => HomeNavigation.maybeOf(context)
              ?.logTimeFor(prefill.date, prefill: prefill);
      return open
          ? _OpenRow(
              gap: gap, onLogThis: onLogThis, logThisTooltip: action.tooltip)
          : _GapRow(
              gap: gap, onLogThis: onLogThis, logThisTooltip: action.tooltip);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (entryProvider.error != null)
          ErrorBanner(message: entryProvider.error!),

        _DateNavRow(
          date: entryProvider.selectedDate,
          onPrevious: () => _shiftDate(context, -1),
          onNext: isToday || isFuture ? null : () => _shiftDate(context, 1),
          onTapDate: () => _pickDate(context),
        ),
        const SizedBox(height: 16),

        if (!isFuture && pendingOnDay.isNotEmpty) ...[
          _PendingMeetingsBanner(
            meetings: pendingOnDay,
            date: entryProvider.selectedDate,
          ),
          const SizedBox(height: 16),
        ],

        if (entryProvider.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (isFuture)
          const _EmptyCard(
            icon: Icons.event_outlined,
            title: 'This day hasn’t happened yet',
            message: 'Insights cover today and earlier. Time logged ahead '
                'shows on Recent.',
          )
        else if (entries.isEmpty)
          _EmptyCard(
            icon: Icons.insights_outlined,
            title: 'Nothing logged',
            message: isToday
                ? 'Log some time and the day’s breakdown appears here.'
                : 'No entries were logged on this day.',
          )
        else ...[
          _StatTiles(
            loggedMinutes: loggedMinutes,
            goalMinutes: goalMinutes,
            coverage: coverage,
            unloggedMinutes: unloggedMinutes,
            insights: insights,
            meetings: meetingLoad(entries),
          ),
          const SizedBox(height: 20),

          _WhereItWent(entries: entries, totalMinutes: loggedMinutes),
          const SizedBox(height: 20),

          if (spans.isEmpty)
            _EmptyCard(
              icon: Icons.schedule_outlined,
              title: 'No clock times on these entries',
              message: entryProvider.tracksByStartEnd
                  ? 'These entries record a duration but not when they '
                      'happened, so gaps can’t be placed on the day. Entries '
                      'logged with Start & End will show up here.'
                  : 'This Harvest account tracks time by duration, so entries '
                      'record how long you worked but not when. Switch the '
                      'account to start/end times in Harvest to see where the '
                      'gaps in the day fall.',
            )
          else if (partial)
            ..._partialDay(
              context,
              insights: insights,
              spans: spans,
              unplaced: unplaced,
              projectNames: {
                for (final e in entries) e.projectId: e.projectName,
              },
              unloggedMinutes: unloggedMinutes,
              windowStart: windowStart,
              windowEnd: windowEnd,
              minGapMinutes: settings.minGapMinutes,
              focus: focus,
              openRow: (gap) => slotRow(gap, open: true),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: Text('Gaps of ${settings.minGapMinutes}m or more',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.text2)),
                ),
                if (insights.longestGapMinutes > 0)
                  Text('Longest ${formatDuration(insights.longestGapMinutes)}',
                      style: TextStyle(fontSize: 11, color: palette.text3)),
              ],
            ),
            const SizedBox(height: 8),
            _DayTimeline(
              insights: insights,
              spans: spans,
              windowStart: windowStart,
              windowEnd: windowEnd,
              focus: focus,
            ),
            if (focus != null) ...[
              const SizedBox(height: 8),
              _FocusLine(gap: focus, without: 'with nothing logged'),
            ],
            const SizedBox(height: 12),
            if (insights.gaps.isEmpty)
              _EmptyCard(
                icon: Icons.check_circle_outline,
                title: 'No significant gaps',
                message: 'Every stretch of the work day so far is accounted '
                    'for. Nicely focused.',
              )
            else
              for (final gap in insights.gaps) slotRow(gap, open: false),
          ],
        ],
      ],
    );
  }
}

class _DateNavRow extends StatelessWidget {
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onTapDate;

  const _DateNavRow({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onTapDate,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous day',
        ),
        Expanded(
          child: InkWell(
            onTap: onTapDate,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                DateFormat('EEEE, d MMM yyyy').format(date),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: palette.text,
                ),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next day',
        ),
      ],
    );
  }
}

class _StatTiles extends StatelessWidget {
  final int loggedMinutes;
  final int goalMinutes;
  final double coverage;
  final int unloggedMinutes;
  final DayInsights insights;
  final MeetingLoad meetings;

  const _StatTiles({
    required this.loggedMinutes,
    required this.goalMinutes,
    required this.coverage,
    required this.unloggedMinutes,
    required this.insights,
    required this.meetings,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _StatTile(
        label: 'Logged',
        value: formatDuration(loggedMinutes),
        detail: 'of ${formatDuration(goalMinutes)} goal',
        emphasis: true,
      ),
      _StatTile(
        label: 'Coverage',
        value: '${(coverage * 100).round()}%',
        detail: 'of the work day',
      ),
      _StatTile(
        label: unloggedMinutes >= 0 ? 'Unlogged' : 'Over goal',
        value: formatDuration(unloggedMinutes.abs()),
        detail: unloggedMinutes < 0
            ? 'past the goal'
            : insights.placement == DayPlacement.partial
                ? 'from totals, no clock times needed'
                : 'still to account for',
        warn: unloggedMinutes < 0,
      ),
      if (meetings.count > 0)
        _StatTile(
          label: 'Meetings',
          value: formatDuration(meetings.minutes),
          detail: '${meetings.percentOfLogged}% of logged · '
              '${meetings.count} meeting${meetings.count == 1 ? '' : 's'}',
        ),
      // Switches need the order of the whole day, so only a fully timed day
      // shows them.
      if (insights.placement == DayPlacement.full)
        _StatTile(
          label: 'Switches',
          value: '${insights.contextSwitches}',
          detail: 'avg ${formatDuration(insights.avgSessionMinutes)} session',
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // One row when each tile has room for its detail line, else three
        // across on a mid width and two on a phone.
        final columns = constraints.maxWidth < 520
            ? 2
            : constraints.maxWidth / tiles.length >= 120
                ? tiles.length
                : 3;
        return GridView.count(
          crossAxisCount: columns,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          children: tiles,
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String detail;
  final bool emphasis;
  final bool warn;

  const _StatTile({
    required this.label,
    required this.value,
    required this.detail,
    this.emphasis = false,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final valueColor = warn
        ? HarvestTokens.warn
        : (emphasis ? palette.brand : palette.text);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: palette.text3)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: valueColor,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(detail,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: palette.text3)),
        ],
      ),
    );
  }
}

/// Per project/task totals for the day, largest first.
class _TaskBreakdown extends StatelessWidget {
  final List<TimeEntry> entries;
  final int totalMinutes;

  const _TaskBreakdown({required this.entries, required this.totalMinutes});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final categories = context.watch<ProjectCategoryProvider>();

    final grouped = groupBy<TimeEntry, String>(
        entries, (e) => '${e.projectId}:${e.taskId}');
    final rows = grouped.values
        .map((group) => (
              entry: group.first,
              minutes:
                  group.fold<double>(0, (s, e) => s + e.hours * 60).round(),
            ))
        .sorted((a, b) => b.minutes.compareTo(a.minutes));

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: categories
                            .categoryFor(row.entry.projectId, fallbackCode: '?')
                            .color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${row.entry.projectName} · ${row.entry.taskName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: palette.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatDuration(row.minutes),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: palette.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: totalMinutes > 0 ? row.minutes / totalMinutes : 0,
                    minHeight: 5,
                    backgroundColor: palette.surface3,
                    valueColor: AlwaysStoppedAnimation(
                      categories
                          .categoryFor(row.entry.projectId, fallbackCode: '?')
                          .color,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A single bar showing worked stretches against the work-day window.
class _DayTimeline extends StatelessWidget {
  final DayInsights insights;
  final List<InsightSpan> spans;
  final int windowStart;
  final int windowEnd;

  /// The longest focus window, outlined.
  final InsightGap? focus;

  const _DayTimeline({
    required this.insights,
    required this.spans,
    required this.windowStart,
    required this.windowEnd,
    this.focus,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final span = windowEnd - windowStart;
    if (span <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 18,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: palette.surface3,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  for (final s in spans)
                    Positioned(
                      left: ((s.start.clamp(windowStart, windowEnd) -
                                  windowStart) /
                              span) *
                          width,
                      width: (((s.end.clamp(windowStart, windowEnd) -
                                      s.start.clamp(windowStart, windowEnd)) /
                                  span) *
                              width)
                          .clamp(1.0, width),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: palette.brand,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  if (focus != null)
                    _focusOutline(focus!, windowStart, span, width),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(formatClock(windowStart),
                style: TextStyle(fontSize: 10, color: palette.text3)),
            Text(
              '${formatDuration(insights.workedMinutes)} covered · '
              '${formatDuration(insights.deadMinutes)} dead',
              style: TextStyle(fontSize: 10, color: palette.text3),
            ),
            Text(formatClock(windowEnd),
                style: TextStyle(fontSize: 10, color: palette.text3)),
          ],
        ),
      ],
    );
  }
}

/// The partial day's timeline: placed spans in their project colours over a
/// hatched background (open — other work or nothing), each titled when wide
/// enough, with hour ticks and a legend naming the projects.
class _PlacedTimeline extends StatelessWidget {
  final List<InsightSpan> spans;
  final int windowStart;
  final int windowEnd;

  /// Harvest project names by id, for the legend.
  final Map<int, String> projectNames;

  /// The longest focus window, outlined.
  final InsightGap? focus;

  const _PlacedTimeline({
    required this.spans,
    required this.windowStart,
    required this.windowEnd,
    required this.projectNames,
    this.focus,
  });

  static const _tickStyle = TextStyle(fontSize: 10);
  static const _blockLabelStyle =
      TextStyle(fontSize: 10, fontWeight: FontWeight.w600);

  static int _projectOf(InsightSpan s) =>
      int.tryParse(s.key.split(':').first) ?? 0;

  /// The legend's name for a project: the part after the last `|`, so
  /// "TFN Project Development | CRT Team" reads "CRT Team".
  static String _shortName(String name) {
    final tail = name.split('|').last.trim();
    return tail.isEmpty ? name.trim() : tail;
  }

  static double _textWidth(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  /// Whole hours inside the window — every hour, or every other on a day
  /// longer than six — keeping each only where its label clears the end
  /// labels and the tick before it.
  List<int> _ticks(double width, TextScaler scaler) {
    final length = windowEnd - windowStart;
    double x(int minutes) => (minutes - windowStart) / length * width;
    double labelWidth(int minutes) =>
        _textWidth(formatClock(minutes), _tickStyle, scaler);
    const clearance = 8.0;

    final step = length > 6 * 60 ? 120 : 60;
    var t = ((windowStart + 59) ~/ 60) * 60;
    // Even hours on a two-hour step, so the ticks read 10:00, 12:00, 14:00.
    if (step == 120 && (t ~/ 60).isOdd) t += 60;

    final ticks = <int>[];
    var leftEdge = labelWidth(windowStart) + clearance;
    final rightEdge = width - labelWidth(windowEnd) - clearance;
    for (; t < windowEnd; t += step) {
      final half = labelWidth(t) / 2;
      if (x(t) - half >= leftEdge && x(t) + half <= rightEdge) {
        ticks.add(t);
        leftEdge = x(t) + half + clearance;
      }
    }
    return ticks;
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final categories = context.watch<ProjectCategoryProvider>();
    final scaler = MediaQuery.textScalerOf(context);
    final length = windowEnd - windowStart;
    if (length <= 0) return const SizedBox.shrink();

    Color colourOf(int projectId) =>
        categories.categoryFor(projectId, fallbackCode: '?').color;

    final tickStyle = _tickStyle.copyWith(color: palette.text3);
    final legendStyle = TextStyle(fontSize: 11, color: palette.text2);
    // One legend entry per project on the timeline, in order of appearance.
    final projects = spans.map(_projectOf).toSet().toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            double x(int minutes) =>
                (minutes.clamp(windowStart, windowEnd) - windowStart) /
                length *
                width;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  key: const ValueKey('placed-timeline'),
                  borderRadius: BorderRadius.circular(5),
                  child: SizedBox(
                    height: 24,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _HatchPainter(color: palette.surface3),
                          ),
                        ),
                        for (final s in spans)
                          if (s.end > windowStart && s.start < windowEnd)
                            _block(s, x(s.start),
                                (x(s.end) - x(s.start)).clamp(1.0, width),
                                colourOf(_projectOf(s)), palette, scaler),
                        if (focus != null)
                          _focusOutline(focus!, windowStart, length, width),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: palette.border),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 14,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned(
                        left: 0,
                        child: Text(formatClock(windowStart), style: tickStyle),
                      ),
                      for (final t in _ticks(width, scaler))
                        Positioned(
                          left: x(t),
                          child: FractionalTranslation(
                            translation: const Offset(-0.5, 0),
                            child: Text(formatClock(t), style: tickStyle),
                          ),
                        ),
                      Positioned(
                        right: 0,
                        child: Text(formatClock(windowEnd), style: tickStyle),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            for (final id in projects)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colourOf(id),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(_shortName(projectNames[id] ?? '?'),
                      style: legendStyle),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(border: Border.all(color: palette.border)),
                    child: CustomPaint(
                      painter:
                          _HatchPainter(color: palette.surface3, spacing: 5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text('Open: other work or nothing', style: legendStyle),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// One placed span, titled inside — cut short with an ellipsis when the
  /// title is longer than the block, left out when the block is too narrow
  /// for more than a letter or two.
  Widget _block(InsightSpan s, double left, double width, Color colour,
      HarvestPalette palette, TextScaler scaler) {
    const padding = 5.0;
    const minTitledWidth = 48.0;
    final fits = s.label.isNotEmpty &&
        (width >= minTitledWidth ||
            _textWidth(s.label, _blockLabelStyle, scaler) + padding * 2 <=
                width);
    final ink =
        ThemeData.estimateBrightnessForColor(colour) == Brightness.dark
            ? Colors.white
            : Colors.black87;
    return Positioned(
      left: left,
      width: width,
      top: 0,
      bottom: 0,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: padding),
        decoration: BoxDecoration(
          color: colour,
          border: Border(right: BorderSide(color: palette.bg)),
        ),
        child: fits
            ? Text(
                s.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: _blockLabelStyle.copyWith(color: ink),
              )
            : null,
      ),
    );
  }
}

/// Diagonal stripes: time that is open rather than placed.
class _HatchPainter extends CustomPainter {
  final Color color;
  final double spacing;

  const _HatchPainter({required this.color, this.spacing = 10});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = spacing / 2
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Lines running up and to the right, stepped along the bottom edge.
    for (var x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
          Offset(x, size.height), Offset(x + size.height, 0), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) =>
      old.color != color || old.spacing != spacing;
}

/// The work logged by duration on a partial day: how much, that it sits
/// somewhere in the open stretches, and which entries it is.
class _UnplacedCard extends StatelessWidget {
  final List<TimeEntry> entries;
  final int unplacedMinutes;
  final int unloggedMinutes;

  const _UnplacedCard({
    required this.entries,
    required this.unplacedMinutes,
    required this.unloggedMinutes,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final categories = context.watch<ProjectCategoryProvider>();
    final ado = context.watch<AdoService>();
    final instances = context.watch<AdoInstanceProvider>().instances;
    // A work item entry whose notes are only the reference would otherwise
    // read as its task ("Development"); its cached title says more.
    String? titleOf(TimeEntry e) {
      final ref = e.adoReference;
      if (ref == null) return null;
      return _cachedWorkItem(
              ado, instances, ref.permalink, ref.id.split('_').last)
          ?.title;
    }

    final strong = TextStyle(fontWeight: FontWeight.w600, color: palette.text);
    final chips = entries
        .map((e) => (entry: e, minutes: (e.hours * 60).round()))
        .sorted((a, b) => b.minutes.compareTo(a.minutes));

    return DashedBorder(
      color: palette.borderStrong,
      strokeWidth: 1,
      radius: 10,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.schedule_outlined,
                  size: 18, color: palette.text3),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 12.5, color: palette.text2, height: 1.45),
                      children: [
                        TextSpan(
                          text: '${formatDuration(unplacedMinutes)} of other '
                              'work isn’t on the timeline.',
                          style: strong,
                        ),
                        const TextSpan(
                          text: ' It was logged by duration, so it sits '
                              'somewhere in the open stretches.',
                        ),
                        if (unloggedMinutes > 0) ...[
                          const TextSpan(text: ' That leaves '),
                          TextSpan(
                            text: '${formatDuration(unloggedMinutes)} of the '
                                'work day unlogged',
                            style: strong,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final c in chips)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: palette.surface2,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: categories
                                      .categoryFor(c.entry.projectId,
                                          fallbackCode: '?')
                                      .color,
                                ),
                              ),
                              const SizedBox(width: 6),
                              // The label gives way to a long title; the
                              // duration always shows.
                              Flexible(
                                child: Text(
                                  entryLabel(c.entry,
                                      workItemTitle: titleOf(c.entry)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: palette.text2),
                                ),
                              ),
                              Text(
                                ' · ${formatDuration(c.minutes)}',
                                style: TextStyle(
                                    fontSize: 11, color: palette.text2),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A stretch between placed spans on a partial day — open, not dead: named
/// by the span before it ("after Standup"), or the one after it when it opens
/// the day.
class _OpenRow extends StatelessWidget {
  final InsightGap gap;

  /// Opens Log Time for this stretch; null disables "Log this".
  final VoidCallback? onLogThis;
  final String logThisTooltip;

  const _OpenRow({
    required this.gap,
    required this.onLogThis,
    required this.logThisTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final previous = gap.previous;
    final next = gap.next;
    final where = previous != null
        ? 'after ${previous.label}'
        : next != null
            ? 'before ${next.label}'
            : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: palette.text3, width: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              formatDuration(gap.minutes),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.text,
              ),
            ),
          ),
          Expanded(
            child: Text(
              where,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: palette.text3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${formatClock(gap.start)} – ${formatClock(gap.end)}',
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
          const SizedBox(width: 8),
          _LogThisButton(onPressed: onLogThis, tooltip: logThisTooltip),
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  final InsightGap gap;

  /// Opens Log Time for this gap; null disables "Log this".
  final VoidCallback? onLogThis;
  final String logThisTooltip;

  const _GapRow({
    required this.gap,
    required this.onLogThis,
    required this.logThisTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HarvestTokens.warn.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatDuration(gap.minutes),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          const Spacer(),
          Text(
            '${formatClock(gap.start)} – ${formatClock(gap.end)}',
            style: TextStyle(fontSize: 11, color: palette.text3),
          ),
          const SizedBox(width: 8),
          _LogThisButton(onPressed: onLogThis, tooltip: logThisTooltip),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.text3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.text)),
                const SizedBox(height: 4),
                Text(message,
                    style: TextStyle(
                        fontSize: 11, color: palette.text3, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The longest focus window drawn over a timeline bar: a success-coloured
/// outline around the stretch, no fill, so what it surrounds still reads.
Widget _focusOutline(InsightGap gap, int windowStart, int length, double width) {
  final left = (gap.start - windowStart) / length * width;
  final right = (gap.end - windowStart) / length * width;
  return Positioned(
    key: const ValueKey('focus-window'),
    left: left,
    width: (right - left).clamp(1.0, width),
    top: 0,
    bottom: 0,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: HarvestTokens.success, width: 2),
        ),
      ),
    ),
  );
}

/// "Longest focus window: 09:20 – 14:30 · 5h 10m with no meetings".
class _FocusLine extends StatelessWidget {
  final InsightGap gap;

  /// How the stretch is free: "with no meetings", "with nothing logged".
  final String without;

  const _FocusLine({required this.gap, required this.without});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: HarvestTokens.success, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Longest focus window: '),
              TextSpan(
                text: '${formatClock(gap.start)} – ${formatClock(gap.end)} · '
                    '${formatDuration(gap.minutes)}',
                style:
                    TextStyle(fontWeight: FontWeight.w600, color: palette.text),
              ),
              TextSpan(text: ' $without'),
            ]),
            style: TextStyle(fontSize: 11.5, color: palette.text2),
          ),
        ),
      ],
    );
  }
}

/// "Log this" on an open stretch or gap. Disabled with its reason in the
/// tooltip when there is nothing to log.
class _LogThisButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const _LogThisButton({required this.onPressed, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.brand,
          side: BorderSide(
              color: onPressed == null ? palette.border : palette.brand),
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 28),
          textStyle:
              const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
        ),
        child: const Text('Log this'),
      ),
    );
  }
}

/// "2 meetings from today aren't logged · Sprint retro and Vendor sync need
/// a project", with Review opening the pending sheet.
class _PendingMeetingsBanner extends StatelessWidget {
  final List<CalendarEvent> meetings;
  final DateTime date;

  const _PendingMeetingsBanner({required this.meetings, required this.date});

  String get _dayWord {
    final days = daysFromToday(date, DateTime.now());
    if (days == 0) return 'today';
    if (days == -1) return 'yesterday';
    return DateFormat('EEE d MMM').format(date);
  }

  String get _who {
    final titles = meetings.map((m) => m.summary.trim()).toList();
    final verb = titles.length == 1 ? 'needs' : 'need';
    final names = switch (titles.length) {
      1 => titles[0],
      2 => '${titles[0]} and ${titles[1]}',
      _ => '${titles[0]}, ${titles[1]} and ${titles.length - 2} more',
    };
    return '$names $verb a project';
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final count = meetings.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: HarvestTokens.warn.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HarvestTokens.warn.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_busy_outlined,
              size: 18, color: HarvestTokens.warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: '$count meeting${count == 1 ? '' : 's'} from '
                      '$_dayWord ${count == 1 ? 'isn’t' : 'aren’t'} logged',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: palette.text),
                ),
                TextSpan(text: ' · $_who'),
              ]),
              style: TextStyle(fontSize: 12, color: palette.text2),
            ),
          ),
          TextButton(
            onPressed: () => showPendingMeetingsSheet(context),
            style: TextButton.styleFrom(foregroundColor: palette.brand),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }
}

/// "Where it went" with its Project · task / Work item switch, remembered in
/// [kInsightsByWorkItemKey].
class _WhereItWent extends StatefulWidget {
  final List<TimeEntry> entries;
  final int totalMinutes;

  const _WhereItWent({required this.entries, required this.totalMinutes});

  @override
  State<_WhereItWent> createState() => _WhereItWentState();
}

class _WhereItWentState extends State<_WhereItWent> {
  bool _byWorkItem = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final byWorkItem = prefs.getBool(kInsightsByWorkItemKey) ?? false;
    if (mounted && byWorkItem != _byWorkItem) {
      setState(() => _byWorkItem = byWorkItem);
    }
  }

  Future<void> _set(bool byWorkItem) async {
    setState(() => _byWorkItem = byWorkItem);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kInsightsByWorkItemKey, byWorkItem);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Where it went',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.text2)),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Project · task')),
                ButtonSegment(value: true, label: Text('Work item')),
              ],
              selected: {_byWorkItem},
              onSelectionChanged: (s) => _set(s.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 11),
                // The chosen side filled with the accent and the other one
                // quiet. A tint on the chosen side read backwards on palettes
                // whose tint is darker than the canvas.
                foregroundColor: palette.text3,
                selectedBackgroundColor: palette.brand,
                selectedForegroundColor: palette.onBrand,
                side: BorderSide(color: palette.borderStrong),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_byWorkItem)
          _WorkItemBreakdown(entries: widget.entries)
        else
          _TaskBreakdown(
              entries: widget.entries, totalMinutes: widget.totalMinutes),
      ],
    );
  }
}

/// Per work item totals for the day, largest first, then everything linked
/// to none. Titles come from the ADO cache, else the entries' notes.
class _WorkItemBreakdown extends StatelessWidget {
  final List<TimeEntry> entries;

  const _WorkItemBreakdown({required this.entries});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final ado = context.watch<AdoService>();
    final instances = context.watch<AdoInstanceProvider>().instances;

    return Column(
      children: [
        for (final group in groupByWorkItem(entries))
          Builder(builder: (context) {
            final id = group.workItemId;
            final cached = id == null
                ? null
                : _cachedWorkItem(ado, instances, group.permalink, id);
            final accent = cached != null
                ? workItemStateColor(cached.state)
                : palette.borderStrong;
            final title = id == null
                ? 'No work item'
                : cached?.title ?? group.notesTitle ?? 'Work item #$id';
            final count = group.entries.length;

            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
              decoration: BoxDecoration(
                color: palette.surface2,
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: accent, width: 3)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text(
                      id == null ? '—' : '#$id',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: cached != null ? accent : palette.text3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: palette.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count ${count == 1 ? 'entry' : 'entries'}',
                    style: TextStyle(fontSize: 11, color: palette.text3),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    formatDuration(group.minutes),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.text,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

/// The cached ADO work item [id], looked up under the instance its
/// [permalink] belongs to; null when no instance matches or the item hasn't
/// been fetched. Insights only reads the cache — Recent's prefetch fills it.
AdoWorkItem? _cachedWorkItem(AdoService ado, List<AdoInstance> instances,
    String? permalink, String id) {
  if (permalink == null || permalink.isEmpty) return null;
  final instance =
      instances.firstWhereOrNull((i) => i.matchesPermalink(permalink));
  return instance == null ? null : ado.getCached(instance.label, id);
}
