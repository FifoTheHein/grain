import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import '../models/project_assignment.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../widgets/time_entry_card.dart';
import '../widgets/weekly_progress_ring.dart';
import '../widgets/error_banner.dart';
import '../theme/harvest_tokens.dart';

class RecentEntriesScreen extends StatefulWidget {
  const RecentEntriesScreen({super.key});

  @override
  State<RecentEntriesScreen> createState() => _RecentEntriesScreenState();
}

class _RecentEntriesScreenState extends State<RecentEntriesScreen> {
  TimeEntryProvider? _timeEntryProvider;
  bool _groupByProject = false;

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
    final picked = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      provider.loadRecentEntries(date: picked);
    }
  }

  void _shiftDate(BuildContext context, int days) {
    final provider = context.read<TimeEntryProvider>();
    final newDate = provider.selectedDate.add(Duration(days: days));
    if (!newDate.isAfter(DateTime.now())) {
      provider.loadRecentEntries(date: newDate);
    }
  }

  Widget _buildGroupedList(BuildContext context, List<TimeEntry> entries) {
    final catProvider = context.watch<ProjectCategoryProvider>();
    final projects = context.watch<AssignmentProvider>().projects;

    final grouped = groupBy<TimeEntry, int>(entries, (e) => e.projectId);

    for (final es in grouped.values) {
      es.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    }

    final groupList = grouped.entries.toList()
      ..sort((a, b) => (b.value.first.createdAt ?? '')
          .compareTo(a.value.first.createdAt ?? ''));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groupList.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _buildProjectGroup(context, groupList[i], catProvider, projects),
          ],
        ],
      ),
    );
  }

  Widget _buildProjectGroup(
    BuildContext context,
    MapEntry<int, List<TimeEntry>> group,
    ProjectCategoryProvider catProvider,
    List<HarvestProject> projects,
  ) {
    final pid = group.key;
    final groupEntries = group.value;
    final proj = projects.firstWhereOrNull((p) => p.id == pid);
    final name = proj?.name ?? groupEntries.first.projectName;
    final clientName = proj?.clientName;
    final fallbackCode = (proj != null && proj.code.isNotEmpty)
        ? proj.code
        : name
            .split(' ')
            .where((w) => w.isNotEmpty)
            .take(3)
            .map((w) => w[0].toUpperCase())
            .join();
    final cat = catProvider.categoryFor(pid, fallbackCode: fallbackCode);
    final total = groupEntries.fold<double>(0, (s, e) => s + e.hours);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProjectGroupHeader(
          projectName: name,
          projectCode: cat.code,
          clientName: clientName,
          color: cat.color,
          tint: cat.tint,
          entryCount: groupEntries.length,
          totalHours: total,
        ),
        const SizedBox(height: 8),
        ...groupEntries.map((e) => TimeEntryCard(entry: e)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TimeEntryProvider>();
    final today = DateTime.now();
    final isToday = provider.selectedDate.year == today.year &&
        provider.selectedDate.month == today.month &&
        provider.selectedDate.day == today.day;

    final sortedEntries = [...provider.entries]
      ..sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));

    return Column(
      children: [
        // Grouping toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilterChip(
                avatar: Icon(
                  _groupByProject
                      ? Icons.folder_open
                      : Icons.folder_outlined,
                  size: 16,
                ),
                label: Text(
                  _groupByProject ? 'Grouped by project' : 'Group by project',
                ),
                selected: _groupByProject,
                onSelected: (v) => setState(() => _groupByProject = v),
              ),
            ],
          ),
        ),
        // Date picker header
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shiftDate(context, -1),
                tooltip: 'Previous day',
              ),
              Expanded(
                child: InkWell(
                  onTap: () => _pickDate(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          isToday
                              ? 'Today'
                              : DateFormat('EEEE').format(provider.selectedDate),
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                        Text(
                          DateFormat('d MMM yyyy')
                              .format(provider.selectedDate),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: isToday ? null : () => _shiftDate(context, 1),
                tooltip: 'Next day',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        LayoutBuilder(
          builder: (ctx, constraints) => _WeekSummaryStrip(
            selectedDate: provider.selectedDate,
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
        const Divider(height: 1),

        // Entries list
        Expanded(
          child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () =>
                      context.read<TimeEntryProvider>().loadRecentEntries(),
                  child: CustomScrollView(
                    slivers: [
                      if (provider.error != null)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: ErrorBanner(message: provider.error!),
                          ),
                        ),
                      if (provider.entries.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                              child: Text('No entries for this day.')),
                        )
                      else if (_groupByProject)
                        SliverToBoxAdapter(
                            child: _buildGroupedList(
                                context, sortedEntries))
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) =>
                                TimeEntryCard(entry: sortedEntries[i]),
                            childCount: sortedEntries.length,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        if (!provider.isLoading)
          _DailyProgressBar(entries: provider.entries, isToday: isToday),
      ],
    );
  }
}

class _DayData {
  final DateTime date;
  final String abbr;
  final double hours;
  final bool isSelected;
  final bool isFuture;

  const _DayData({
    required this.date,
    required this.abbr,
    required this.hours,
    required this.isSelected,
    required this.isFuture,
  });
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
    final dayOfWeek = selectedDate.weekday;
    final monday = selectedDate.subtract(Duration(days: dayOfWeek - 1));
    final selectedStr = fmt.format(selectedDate);
    final today = DateTime.now();
    final todayStr = fmt.format(today);

    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      final dayStr = fmt.format(day);
      return _DayData(
        date: day,
        abbr: _dayAbbrs[i],
        hours: weeklyTotals[dayStr] ?? 0,
        isSelected: dayStr == selectedStr,
        isFuture: day.isAfter(today) && dayStr != todayStr,
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

  Widget _buildCompact(
      BuildContext context, List<_DayData> days, double weekTotal) {
    final colorScheme = Theme.of(context).colorScheme;
    final weeklyGoal = context.select<ProjectCategoryProvider, double>(
      (p) => p.weeklyGoalHours,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          ...days.map((d) {
            final textColor = d.isSelected
                ? colorScheme.primary
                : d.isFuture
                    ? colorScheme.onSurface.withValues(alpha: 0.3)
                    : colorScheme.onSurfaceVariant;
            return Expanded(
              child: InkWell(
                onTap: d.isFuture ? null : () => onDayTap(d.date),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      d.abbr,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight: d.isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isLoading ? '–' : _fmt(d.hours),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: textColor,
                            fontWeight: d.isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }),
          Container(
            padding: const EdgeInsets.only(left: 8),
            decoration: const BoxDecoration(
              border: Border(
                  left: BorderSide(color: Color(0xFFE8E1D4))),
            ),
            child: Center(
              child: WeeklyProgressRing(
                hours: isLoading ? 0 : weekTotal,
                goal: weeklyGoal,
                size: 64,
                stroke: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmphasized(
      BuildContext context, List<_DayData> days, double weekTotal) {
    final dailyGoal = context.select<ProjectCategoryProvider, double>(
      (provider) => provider.dailyGoalHours,
    );
    final weeklyGoal = context.select<ProjectCategoryProvider, double>(
      (provider) => provider.weeklyGoalHours,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Container(
        decoration: BoxDecoration(
          color: HarvestTokens.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HarvestTokens.border),
        ),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
        child: Row(
          children: [
            ...days.map((d) {
              final textColor = d.isSelected
                  ? HarvestTokens.brand600
                  : d.isFuture
                      ? HarvestTokens.text4
                      : HarvestTokens.text;
              final labelColor = d.isSelected
                  ? HarvestTokens.brand
                  : d.isFuture
                      ? HarvestTokens.text4
                      : HarvestTokens.text3;
              final isOver = d.hours > dailyGoal;
              final progress = (d.hours / dailyGoal).clamp(0.0, 1.0);

              return Expanded(
                child: GestureDetector(
                  onTap: d.isFuture ? null : () => onDayTap(d.date),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: d.isSelected
                          ? HarvestTokens.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: d.isSelected
                            ? HarvestTokens.brandTint2
                            : Colors.transparent,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          d.abbr.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                            color: labelColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${d.date.day}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          d.isFuture || isLoading ? '–' : _fmt(d.hours),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: d.isSelected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: SizedBox(
                            height: 3,
                            child: LinearProgressIndicator(
                              value: d.isFuture ? 0 : progress,
                              backgroundColor: HarvestTokens.surface3,
                              color: isOver
                                  ? HarvestTokens.warn
                                  : HarvestTokens.brand,
                              minHeight: 3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            Container(
              padding: const EdgeInsets.only(left: 8),
              decoration: const BoxDecoration(
                border: Border(
                    left: BorderSide(color: Color(0xFFE8E1D4))),
              ),
              child: Center(
                child: WeeklyProgressRing(
                  hours: isLoading ? 0 : weekTotal,
                  goal: weeklyGoal,
                  size: 76,
                  stroke: 7,
                ),
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

  const _DailyProgressBar({required this.entries, required this.isToday});

  String _fmt(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final catProvider = context.watch<ProjectCategoryProvider>();
    final goal = catProvider.dailyGoalHours;
    final total =
        entries.fold<double>(0, (sum, e) => sum + (e.hours as double));
    final isOver = total > goal;
    final progress = (total / goal).clamp(0.0, 1.0);
    final overflow = total - goal;

    double? expectedHours;
    double? expectedRatio;
    if (isToday) {
      final now = DateTime.now();
      final startMinutes =
          catProvider.workDayStart.hour * 60 + catProvider.workDayStart.minute;
      final endMinutes =
          catProvider.workDayEnd.hour * 60 + catProvider.workDayEnd.minute;
      final nowMinutes = now.hour * 60 + now.minute;
      final elapsedRatio = ((nowMinutes - startMinutes) /
              (endMinutes - startMinutes))
          .clamp(0.0, 1.0);
      expectedHours = elapsedRatio * goal;
      expectedRatio = (expectedHours / goal).clamp(0.0, 1.0);
    }

    final colorScheme = Theme.of(context).colorScheme;
    final barColor = isOver ? HarvestTokens.warn : HarvestTokens.brand;

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
                'Total: ${_fmt(total)}',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isOver ? HarvestTokens.warn : colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (expectedHours != null)
                Text(
                  'Expected: ${_fmt(expectedHours)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              Text(
                isOver
                    ? '+${_fmt(overflow)} over goal'
                    : '${_fmt(goal - total)} remaining',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isOver
                          ? HarvestTokens.warn
                          : colorScheme.onSurfaceVariant,
                    ),
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
                Container(
                  height: 8,
                  color: colorScheme.surfaceContainerHighest,
                ),
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
                      child: Container(
                        width: 2,
                        height: 8,
                        color: HarvestTokens.brand600,
                      ),
                    ),
                  ),
                // Expected time tick marker
                if (expectedRatio != null)
                  FractionallySizedBox(
                    widthFactor: expectedRatio,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: 2,
                        height: 8,
                        color: colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
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

class _ProjectGroupHeader extends StatelessWidget {
  final String projectName;
  final String projectCode;
  final String? clientName;
  final Color color;
  final Color tint;
  final int entryCount;
  final double totalHours;

  const _ProjectGroupHeader({
    required this.projectName,
    required this.projectCode,
    this.clientName,
    required this.color,
    required this.tint,
    required this.entryCount,
    required this.totalHours,
  });

  String _fmt(double hours) {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: HarvestTokens.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: tint,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                projectCode,
                style: TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  Text(
                    projectName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HarvestTokens.text,
                    ),
                  ),
                  if (clientName != null) ...[
                    const Text(
                      '·',
                      style: TextStyle(
                          color: HarvestTokens.text4, fontSize: 11),
                    ),
                    Text(
                      clientName!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: HarvestTokens.text3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: HarvestTokens.text3,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _fmt(totalHours),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
