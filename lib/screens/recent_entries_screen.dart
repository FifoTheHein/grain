import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/future_days.dart';
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
import '../widgets/time_entry_card.dart';
import '../widgets/upcoming_tag.dart';
import '../widgets/weekly_progress_ring.dart';
import 'home_screen.dart';

/// How faded a future day is on the week strip: there, and tappable, but
/// plainly not a day that has happened.
const double kFutureDayOpacity = 0.38;

class RecentEntriesScreen extends StatefulWidget {
  const RecentEntriesScreen({super.key});

  @override
  State<RecentEntriesScreen> createState() => _RecentEntriesScreenState();
}

class _RecentEntriesScreenState extends State<RecentEntriesScreen> {
  TimeEntryProvider? _timeEntryProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<TimeEntryProvider>();
    if (provider != _timeEntryProvider) {
      _timeEntryProvider?.removeListener(_onEntriesChanged);
      _timeEntryProvider = provider;
      _timeEntryProvider!.addListener(_onEntriesChanged);
      // Entries may already be loaded (e.g. switching tabs) — prefetch now.
      _onEntriesChanged();
    }
  }

  @override
  void dispose() {
    _timeEntryProvider?.removeListener(_onEntriesChanged);
    super.dispose();
  }

  void _onEntriesChanged() {
    final provider = _timeEntryProvider;
    if (provider == null || provider.isLoading) return;
    final adoService = context.read<AdoService>();
    final instances = context.read<AdoInstanceProvider>().instances;
    adoService.prefetchForEntries(provider.entries, instances);
  }

  Future<void> _pickDate(BuildContext context) async {
    final provider = context.read<TimeEntryProvider>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: clampToSelectable(provider.selectedDate, now),
      firstDate: DateTime(2020),
      lastDate: latestSelectableDate(now),
    );
    if (picked != null) {
      provider.loadRecentEntries(date: picked);
    }
  }

  /// One day back or forward, no further than [latestSelectableDate].
  /// Crossing into another week refetches, since the provider loads the
  /// selected date's Monday–Sunday.
  void _shiftDate(BuildContext context, int days) {
    final provider = context.read<TimeEntryProvider>();
    final d = provider.selectedDate;
    final newDate = DateTime(d.year, d.month, d.day + days);
    if (isSelectableDay(newDate, DateTime.now())) {
      provider.loadRecentEntries(date: newDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimeEntryProvider>();
    final now = DateTime.now();
    final selected = provider.selectedDate;
    final isToday = provider.isSelectedDateToday;
    final isFuture = isFutureDay(selected, now);
    final canGoForward = isSelectableDay(
        DateTime(selected.year, selected.month, selected.day + 1), now);
    final pendingMeetings = context.watch<CalendarImportProvider>().pending.length;

    final sortedEntries = [...provider.entries]..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

    return Column(
      children: [
        if (provider.showNewDayBanner)
          _NewDayBanner(onGoToToday: () => provider.loadRecentEntries(date: DateTime.now())),
        if (pendingMeetings > 0)
          _PendingMeetingsBanner(
            count: pendingMeetings,
            onReview: () => showPendingMeetingsSheet(context),
          ),
        _DateHeader(
          heading: dayHeading(selected, now),
          onPrevious: () => _shiftDate(context, -1),
          onNext: canGoForward ? () => _shiftDate(context, 1) : null,
          onPick: () => _pickDate(context),
          onToday: isToday ? null : () => provider.loadRecentEntries(date: DateTime.now()),
        ),
        const Divider(height: 1),
        LayoutBuilder(
          builder: (ctx, constraints) => _WeekSummaryStrip(
            selectedDate: selected,
            weeklyTotals: provider.weeklyTotals,
            isLoading: provider.isLoading,
            emphasized: constraints.maxWidth >= HarvestTokens.kWideBreakpoint,
            onDayTap: (date) {
              final tappedDate = DateTime(date.year, date.month, date.day);
              final selectedDate = DateTime(
                provider.selectedDate.year,
                provider.selectedDate.month,
                provider.selectedDate.day,
              );

              if (provider.isLoading || tappedDate == selectedDate) {
                return;
              }

              context.read<TimeEntryProvider>().loadRecentEntries(date: date);
            },
          ),
        ),
        const SizedBox(height: 4),

        // Entries list
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () => context.read<TimeEntryProvider>().loadRecentEntries(),
                  child: CustomScrollView(
                    slivers: [
                      if (provider.error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: ErrorBanner(message: provider.error!),
                          ),
                        ),
                      if (provider.entries.isEmpty && isFuture)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _EmptyFutureDay(
                            date: selected,
                            onLogTime: () => HomeNavigation.maybeOf(context)?.logTimeFor(selected),
                          ),
                        )
                      else if (provider.entries.isEmpty)
                        const SliverFillRemaining(child: Center(child: Text('No entries for this day.')))
                      else ...[
                        if (isFuture) const SliverToBoxAdapter(child: _LoggedAheadNote()),
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => TimeEntryCard(entry: sortedEntries[i]),
                            childCount: sortedEntries.length,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        ),
        if (!provider.isLoading)
          _DailyProgressBar(entries: provider.entries, isToday: isToday, isFuture: isFuture),
      ],
    );
  }
}

/// ‹ · "Tomorrow [UPCOMING]" over "Tue 13 Oct 2026" · ›, with a Today jump
/// beside ‹ whenever another day is showing. The label opens the picker.
class _DateHeader extends StatelessWidget {
  final DayHeading heading;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback? onToday;

  const _DateHeader({
    required this.heading,
    required this.onPrevious,
    required this.onNext,
    required this.onPick,
    required this.onToday,
  });

  // Both sides take the same width, so the label stays centred whether or
  // not the Today jump is showing.
  static const _sideWidth = 108.0;

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: _sideWidth,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: onPrevious,
                  tooltip: 'Previous day',
                ),
                if (onToday != null)
                  Flexible(
                    child: OutlinedButton(
                      key: const ValueKey('jump-today'),
                      onPressed: onToday,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.brandInkOn(palette.bg),
                        side: BorderSide(color: palette.brand),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Today'),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            heading.title,
                            key: const ValueKey('day-title'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: heading.isToday ? palette.brandInkOn(palette.bg) : palette.text,
                            ),
                          ),
                        ),
                        if (heading.upcoming) ...[
                          const SizedBox(width: 6),
                          const UpcomingTag(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      heading.subtitle,
                      key: const ValueKey('day-subtitle'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: palette.text2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            width: _sideWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: onNext,
                tooltip: 'Next day',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Over a future day's entries: they are planned, and already counted.
class _LoggedAheadNote extends StatelessWidget {
  const _LoggedAheadNote();

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
      child: DashedBorder(
        key: const ValueKey('logged-ahead-note'),
        color: palette.borderStrong,
        strokeWidth: 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.event_outlined, size: 16, color: palette.text2),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Logged ahead. Harvest already counts these in this week’s total.',
                  style: TextStyle(fontSize: 12, color: palette.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// An empty future day: nothing to list, so offer to log something for it.
class _EmptyFutureDay extends StatelessWidget {
  final DateTime date;
  final VoidCallback onLogTime;

  const _EmptyFutureDay({required this.date, required this.onLogTime});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
      child: Column(
        children: [
          Icon(Icons.event_outlined, size: 26, color: palette.text3),
          const SizedBox(height: 10),
          Text(
            'Nothing logged for ${DateFormat('EEEE').format(date)} yet',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: palette.text),
          ),
          const SizedBox(height: 6),
          Text(
            'Leave, a planned workshop, a meeting you already know about…',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: palette.text3),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const ValueKey('log-time-for-day'),
            onPressed: onLogTime,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: Text('Log time for ${DateFormat('EEE d MMM').format(date)}'),
            style: FilledButton.styleFrom(
              backgroundColor: palette.brandTint2,
              foregroundColor: palette.text,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayData {
  final DateTime date;
  final String abbr;
  final double hours;
  final bool isSelected;
  final bool isToday;
  final bool isFuture;

  /// Within [latestSelectableDate]. A future day past it is still drawn,
  /// faded, but does nothing when tapped.
  final bool isSelectable;

  const _DayData({
    required this.date,
    required this.abbr,
    required this.hours,
    required this.isSelected,
    required this.isToday,
    required this.isFuture,
    required this.isSelectable,
  });
}

/// The colours one day takes on the strip, shared by both layouts.
///
/// - selected, today or earlier: a solid brand tile, onBrand ink;
/// - selected, future: a dashed outline, normal ink;
/// - today, not selected: the number in the accent (see
///   [HarvestPalette.brandInkOn]) and a dot under it;
/// - future: faded to [kFutureDayOpacity] as a whole.
class _DayStyle {
  final Color? fill;
  final bool dashed;
  final Color label;
  final Color number;
  final Color hours;
  final Color dot;

  const _DayStyle({
    required this.fill,
    required this.dashed,
    required this.label,
    required this.number,
    required this.hours,
    required this.dot,
  });

  factory _DayStyle.of(_DayData d, HarvestPalette palette, Color background) {
    if (d.isSelected && !d.isFuture) {
      return _DayStyle(
        fill: palette.brand,
        dashed: false,
        label: palette.onBrand,
        number: palette.onBrand,
        hours: palette.onBrand,
        dot: palette.onBrand,
      );
    }
    return _DayStyle(
      fill: null,
      dashed: d.isSelected,
      label: d.isSelected ? palette.text : palette.text3,
      number: d.isToday ? palette.brandInkOn(background) : palette.text,
      hours: d.isSelected ? palette.text : palette.text2,
      dot: palette.brandInkOn(background),
    );
  }
}

class _WeekSummaryStrip extends StatelessWidget {
  final DateTime selectedDate;
  final Map<String, double> weeklyTotals;
  final bool isLoading;
  final void Function(DateTime) onDayTap;
  final bool emphasized;

  const _WeekSummaryStrip({
    required this.selectedDate,
    required this.weeklyTotals,
    required this.isLoading,
    required this.onDayTap,
    this.emphasized = false,
  });

  static const _dayAbbrs = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String _fmt(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0 && m == 0) return '–';
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  List<_DayData> _buildDays() {
    final fmt = DateFormat('yyyy-MM-dd');
    final monday = DateTime(selectedDate.year, selectedDate.month, selectedDate.day - (selectedDate.weekday - 1));
    final selectedStr = fmt.format(selectedDate);
    final now = DateTime.now();

    return List.generate(7, (i) {
      final day = DateTime(monday.year, monday.month, monday.day + i);
      final dayStr = fmt.format(day);
      final offset = daysFromToday(day, now);
      return _DayData(
        date: day,
        abbr: _dayAbbrs[i],
        hours: weeklyTotals[dayStr] ?? 0,
        isSelected: dayStr == selectedStr,
        isToday: offset == 0,
        isFuture: offset > 0,
        isSelectable: isSelectableDay(day, now),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildDays();
    double weekTotal = 0;
    for (final v in weeklyTotals.values) {
      weekTotal += v;
    }
    if (emphasized) return _buildEmphasized(context, days, weekTotal);
    return _buildCompact(context, days, weekTotal);
  }

  /// Faded when future, dashed when a selected future day, and wired to
  /// [onDayTap] only within the cap.
  Widget _dayFrame({
    required _DayData d,
    required _DayStyle style,
    required HarvestPalette palette,
    required double radius,
    required EdgeInsets margin,
    required EdgeInsets padding,
    required Widget child,
  }) {
    Widget tile = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: style.fill,
        borderRadius: BorderRadius.circular(radius),
        border: style.fill != null ? Border.all(color: style.fill!, width: 1.5) : null,
      ),
      child: child,
    );
    if (style.dashed) {
      tile = DashedBorder(color: palette.text2, radius: radius, child: tile);
    }
    // A selected future day is the one you are looking at, so it is not
    // faded with the rest of the week ahead.
    if (d.isFuture && !d.isSelected) {
      tile = Opacity(opacity: kFutureDayOpacity, child: tile);
    }
    return Expanded(
      child: Padding(
        padding: margin,
        child: Semantics(
          button: d.isSelectable,
          selected: d.isSelected,
          enabled: d.isSelectable,
          label: '${DateFormat('EEEE d MMMM').format(d.date)}'
              '${d.isToday ? ', today' : ''}'
              '${d.isFuture ? ', upcoming' : ''}'
              ', ${_fmt(d.hours) == '–' ? 'nothing logged' : _fmt(d.hours)}',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('week-day-${DateFormat('yyyy-MM-dd').format(d.date)}'),
            borderRadius: BorderRadius.circular(radius),
            onTap: d.isSelectable ? () => onDayTap(d.date) : null,
            child: tile,
          ),
        ),
      ),
    );
  }

  Widget _todayDot(_DayData d, _DayStyle style) => SizedBox(
        height: 4,
        child: d.isToday
            ? Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: style.dot, shape: BoxShape.circle),
              )
            : null,
      );

  Widget _buildCompact(BuildContext context, List<_DayData> days, double weekTotal) {
    final palette = HarvestTokens.of(context);
    final weeklyGoal = context.select<ProjectCategoryProvider, double>((p) => p.weeklyGoalHours);

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 8),
      child: Row(
        children: [
          ...days.map((d) {
            final style = _DayStyle.of(d, palette, palette.bg);
            return _dayFrame(
              d: d,
              style: style,
              palette: palette,
              radius: 10,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    d.abbr.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: style.label),
                  ),
                  Text(
                    '${d.date.day}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: d.isFuture ? FontWeight.w500 : FontWeight.w700,
                      color: style.number,
                      height: 1.25,
                    ),
                  ),
                  Text(
                    isLoading ? '–' : _fmt(d.hours),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(fontSize: 10.5, color: style.hours),
                  ),
                  const SizedBox(height: 2),
                  _todayDot(d, style),
                ],
              ),
            );
          }),
          Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.only(left: 8),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: palette.border)),
            ),
            child: Center(
              child: WeeklyProgressRing(hours: isLoading ? 0 : weekTotal, goal: weeklyGoal, size: 64, stroke: 6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmphasized(BuildContext context, List<_DayData> days, double weekTotal) {
    final palette = HarvestTokens.of(context);
    final dailyGoal = context.select<ProjectCategoryProvider, double>((provider) => provider.dailyGoalHours);
    final weeklyGoal = context.select<ProjectCategoryProvider, double>((provider) => provider.weeklyGoalHours);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        child: Row(
          children: [
            ...days.map((d) {
              final style = _DayStyle.of(d, palette, palette.surface2);
              final solid = style.fill != null;
              final isOver = d.hours > dailyGoal;
              final progress = (d.hours / dailyGoal).clamp(0.0, 1.0);

              return _dayFrame(
                d: d,
                style: style,
                palette: palette,
                radius: 8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.abbr.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.6,
                        color: style.label,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.date.day}',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 18,
                        fontWeight: d.isFuture ? FontWeight.w500 : FontWeight.w600,
                        letterSpacing: -0.4,
                        color: style.number,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isLoading ? '–' : _fmt(d.hours),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: d.isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontStyle: d.isFuture && d.hours > 0 ? FontStyle.italic : FontStyle.normal,
                        color: style.hours,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: solid ? palette.onBrand.withValues(alpha: 0.3) : palette.surface3,
                          color: solid
                              ? palette.onBrand
                              : (isOver ? HarvestTokens.warn : palette.brand)
                                  .withValues(alpha: d.isFuture ? 0.5 : 1),
                          minHeight: 3,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: palette.border)),
              ),
              child: Center(
                child: WeeklyProgressRing(hours: isLoading ? 0 : weekTotal, goal: weeklyGoal, size: 76, stroke: 7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyProgressBar extends StatelessWidget {
  final List entries;
  final bool isToday;

  /// A day not yet reached: the total is what was logged ahead, and there is
  /// no expected-by-now marker.
  final bool isFuture;

  const _DailyProgressBar({required this.entries, required this.isToday, this.isFuture = false});

  String _fmt(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0 && m == 0) return '0h';
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final catProvider = context.watch<ProjectCategoryProvider>();
    final goal = catProvider.dailyGoalHours;
    final total = entries.fold<double>(0, (sum, e) => sum + (e.hours as double));
    final isOver = total > goal;
    final progress = (total / goal).clamp(0.0, 1.0);
    final overflow = total - goal;

    double? expectedHours;
    double? expectedRatio;
    if (isToday) {
      final now = DateTime.now();
      final startMinutes = catProvider.workDayStart.hour * 60 + catProvider.workDayStart.minute;
      final endMinutes = catProvider.workDayEnd.hour * 60 + catProvider.workDayEnd.minute;
      final nowMinutes = now.hour * 60 + now.minute;
      final elapsedRatio = ((nowMinutes - startMinutes) / (endMinutes - startMinutes)).clamp(0.0, 1.0);
      expectedHours = elapsedRatio * goal;
      expectedRatio = (expectedHours / goal).clamp(0.0, 1.0);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final palette = HarvestTokens.of(context);
    final barColor = (isOver ? HarvestTokens.warn : palette.brand).withValues(alpha: isFuture ? 0.5 : 1);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isFuture ? 'Logged ahead: ${_fmt(total)}' : 'Total: ${_fmt(total)}',
                key: const ValueKey('day-total'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: isOver ? HarvestTokens.warn : colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (expectedHours != null)
                Text(
                  'Expected: ${_fmt(expectedHours)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              Text(
                isOver
                    ? '+${_fmt(overflow)} over goal'
                    : isFuture
                    ? '${_fmt(goal - total)} to goal'
                    : '${_fmt(goal - total)} remaining',
                key: const ValueKey('day-remaining'),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: isOver ? HarvestTokens.warn : colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                // Background track
                Container(height: 8, color: colorScheme.surfaceContainerHighest),
                // Filled portion
                FractionallySizedBox(
                  widthFactor: progress,
                  child: Container(height: 8, color: barColor),
                ),
                // Overflow marker at goal boundary
                if (isOver)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(width: 2, height: 8, color: palette.brand600),
                    ),
                  ),
                // Expected time tick marker
                if (expectedRatio != null)
                  FractionallySizedBox(
                    widthFactor: expectedRatio,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(width: 2, height: 8, color: colorScheme.onSurface.withValues(alpha: 0.45)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NewDayBanner extends StatelessWidget {
  final VoidCallback onGoToToday;
  const _NewDayBanner({required this.onGoToToday});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: HarvestTokens.warn.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: HarvestTokens.warn.withValues(alpha: 0.40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wb_sunny_outlined, size: 16, color: HarvestTokens.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  "Hey, it's a new day!",
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: HarvestTokens.warn),
                ),
                GestureDetector(
                  onTap: onGoToToday,
                  child: Text(
                    'Go to today\'s timesheet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.brand,
                      decoration: TextDecoration.underline,
                      decorationColor: palette.brand,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown while the calendar import holds meetings no rule or default placed.
class _PendingMeetingsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onReview;
  const _PendingMeetingsBanner({required this.count, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      decoration: BoxDecoration(
        color: palette.brandTint,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.brand.withValues(alpha: 0.40)),
      ),
      child: InkWell(
        onTap: onReview,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.event_note_outlined, size: 16, color: palette.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count meeting${count == 1 ? '' : 's'} need a project',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: palette.text),
                ),
              ),
              Text(
                'Review',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.brand),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
