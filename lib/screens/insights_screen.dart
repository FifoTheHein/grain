import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/day_insights.dart';
import '../models/time_entry.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../theme/harvest_tokens.dart';
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
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) provider.loadRecentEntries(date: picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final entryProvider = context.watch<TimeEntryProvider>();
    final settings = context.watch<ProjectCategoryProvider>();

    final entries = entryProvider.entries;
    final isToday = entryProvider.isSelectedDateToday;

    // Entries carrying clock times drive the gap analysis; the rest still
    // count towards the day's total.
    final spans = entries.map((e) => e.span).nonNulls.toList();
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
    );

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
          onNext: isToday ? null : () => _shiftDate(context, 1),
          onTapDate: () => _pickDate(context),
        ),
        const SizedBox(height: 16),

        if (entryProvider.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
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
            hasSpans: spans.isNotEmpty,
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
  final bool hasSpans;

  const _StatTiles({
    required this.loggedMinutes,
    required this.goalMinutes,
    required this.coverage,
    required this.unloggedMinutes,
    required this.insights,
    required this.hasSpans,
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
        detail: unloggedMinutes >= 0 ? 'still to account for' : 'past the goal',
        warn: unloggedMinutes < 0,
      ),
      if (hasSpans)
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
