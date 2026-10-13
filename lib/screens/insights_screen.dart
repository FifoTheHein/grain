import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/day_insights.dart';
import '../models/entry_display.dart';
import '../models/future_days.dart';
import '../models/time_entry.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../theme/harvest_tokens.dart';
import '../widgets/dashed_border.dart';
import '../widgets/error_banner.dart';

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
    required int unloggedMinutes,
    required int windowStart,
    required int windowEnd,
    required int minGapMinutes,
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
        placedLabel: allCalendar
            ? 'Meeting, from your calendar'
            : 'Placed: meetings and timed entries',
      ),
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
        for (final gap in insights.gaps) _OpenRow(gap: gap),
    ];
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
          ),
          const SizedBox(height: 20),

          Text('Where it went',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.text2)),
          const SizedBox(height: 8),
          _TaskBreakdown(entries: entries, totalMinutes: loggedMinutes),
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
              unloggedMinutes: unloggedMinutes,
              windowStart: windowStart,
              windowEnd: windowEnd,
              minGapMinutes: settings.minGapMinutes,
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
            ),
            const SizedBox(height: 12),
            if (insights.gaps.isEmpty)
              _EmptyCard(
                icon: Icons.check_circle_outline,
                title: 'No significant gaps',
                message: 'Every stretch of the work day so far is accounted '
                    'for. Nicely focused.',
              )
            else
              for (final gap in insights.gaps) _GapRow(gap: gap),
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

  const _StatTiles({
    required this.loggedMinutes,
    required this.goalMinutes,
    required this.coverage,
    required this.unloggedMinutes,
    required this.insights,
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
        final columns = constraints.maxWidth >= 520 ? tiles.length : 2;
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

  const _DayTimeline({
    required this.insights,
    required this.spans,
    required this.windowStart,
    required this.windowEnd,
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
/// hatched background (open — other work or nothing), with hour ticks and a
/// legend.
class _PlacedTimeline extends StatelessWidget {
  final List<InsightSpan> spans;
  final int windowStart;
  final int windowEnd;
  final String placedLabel;

  const _PlacedTimeline({
    required this.spans,
    required this.windowStart,
    required this.windowEnd,
    required this.placedLabel,
  });

  /// Whole hours between the window's ends, every two hours on a long day,
  /// skipping any that would crowd an end label.
  List<int> _ticks() {
    final length = windowEnd - windowStart;
    final step = length > 6 * 60 ? 120 : 60;
    final ticks = <int>[];
    var t = ((windowStart + 59) ~/ 60) * 60;
    // Even hours on a two-hour step, so the ticks read 10:00, 12:00, 14:00.
    if (step == 120 && (t ~/ 60).isOdd) t += 60;
    for (; t < windowEnd; t += step) {
      if (t - windowStart >= 45 && windowEnd - t >= 45) ticks.add(t);
    }
    return ticks;
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final categories = context.watch<ProjectCategoryProvider>();
    final length = windowEnd - windowStart;
    if (length <= 0) return const SizedBox.shrink();

    Color colourOf(InsightSpan s) {
      final projectId = int.tryParse(s.key.split(':').first) ?? 0;
      return categories.categoryFor(projectId, fallbackCode: '?').color;
    }

    final tickStyle = TextStyle(fontSize: 10, color: palette.text3);
    final legendStyle = TextStyle(fontSize: 11, color: palette.text2);

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
                            Positioned(
                              left: x(s.start),
                              width: (x(s.end) - x(s.start)).clamp(1.0, width),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: colourOf(s),
                                  border: Border(
                                      right: BorderSide(color: palette.bg)),
                                ),
                              ),
                            ),
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
                      for (final t in _ticks())
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: spans.isEmpty ? palette.brand : colourOf(spans.first),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 6),
                Text(placedLabel, style: legendStyle),
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
                              Flexible(
                                child: Text(
                                  '${entryLabel(c.entry)} · '
                                  '${formatDuration(c.minutes)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11, color: palette.text2),
                                ),
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

  const _OpenRow({required this.gap});

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
        ],
      ),
    );
  }
}

class _GapRow extends StatelessWidget {
  final InsightGap gap;

  const _GapRow({required this.gap});

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
