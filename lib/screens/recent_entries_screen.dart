import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/project_assignment.dart';
import '../models/project_category.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/assignment_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../services/ado_service.dart';
import '../widgets/time_entry_card.dart';
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
  void initState() {
    super.initState();
    _loadGroupPref();
  }

  Future<void> _loadGroupPref() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _groupByProject = prefs.getBool('group_by_project') ?? false;
      });
    }
  }

  Future<void> _toggleGrouping() async {
    final next = !_groupByProject;
    setState(() => _groupByProject = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('group_by_project', next);
  }

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

    // Preserve first-occurrence order
    final groupOrder = <int>[];
    final groups = <int, List<TimeEntry>>{};
    for (final e in entries) {
      if (!groups.containsKey(e.projectId)) {
        groups[e.projectId] = [];
        groupOrder.add(e.projectId);
      }
      groups[e.projectId]!.add(e);
    }

    return Column(
      children: [
        for (final pid in groupOrder) ...[
          const SizedBox(height: 8),
          Builder(builder: (ctx) {
            final proj = projects.firstWhere(
              (p) => p.id == pid,
              orElse: () => HarvestProject(
                id: pid,
                name: groups[pid]!.first.projectName,
                code: '',
                tasks: [],
              ),
            );
            final fallback = proj.code.isNotEmpty
                ? proj.code
                : proj.name
                    .split(' ')
                    .where((w) => w.isNotEmpty)
                    .take(3)
                    .map((w) => w[0].toUpperCase())
                    .join();
            final cat = catProvider.categoryFor(pid, fallbackCode: fallback);
            final groupEntries = groups[pid]!;
            final total = groupEntries.fold<double>(0, (s, e) => s + e.hours);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProjectGroupHeader(
                  projectName: proj.name,
                  category: cat,
                  entryCount: groupEntries.length,
                  totalHours: total,
                ),
                const Divider(height: 1),
                const SizedBox(height: 6),
                for (final e in groupEntries) TimeEntryCard(entry: e),
              ],
            );
          }),
        ],
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

    return Column(
      children: [
        // Grouping toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Tooltip(
                message: _groupByProject ? 'Flat list' : 'Group by project',
                child: IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: _groupByProject
                        ? HarvestTokens.brand
                        : HarvestTokens.text3,
                  ),
                  onPressed: _toggleGrouping,
                ),
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
        _WeekSummaryStrip(
          selectedDate: provider.selectedDate,
          weeklyTotals: provider.weeklyTotals,
          isLoading: provider.isLoading,
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
                                context, provider.entries))
                      else
                        SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) =>
                                TimeEntryCard(entry: provider.entries[i]),
                            childCount: provider.entries.length,
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        if (!provider.isLoading) _DailyProgressBar(entries: provider.entries),
      ],
    );
  }
}

class _WeekSummaryStrip extends StatelessWidget {
  final DateTime selectedDate;
  final Map<String, double> weeklyTotals;
  final bool isLoading;
  final void Function(DateTime) onDayTap;

  const _WeekSummaryStrip({
    required this.selectedDate,
    required this.weeklyTotals,
    required this.isLoading,
    required this.onDayTap,
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('yyyy-MM-dd');
    final dayOfWeek = selectedDate.weekday; // 1=Mon, 7=Sun
    final monday = selectedDate.subtract(Duration(days: dayOfWeek - 1));
    final selectedStr = fmt.format(selectedDate);
    final today = DateTime.now();
    final todayStr = fmt.format(today);

    double weekTotal = 0;
    for (final v in weeklyTotals.values) {
      weekTotal += v;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Seven day columns
          ...List.generate(7, (i) {
            final day = monday.add(Duration(days: i));
            final dayStr = fmt.format(day);
            final isSelected = dayStr == selectedStr;
            final isFuture = day.isAfter(today) && dayStr != todayStr;
            final hours = weeklyTotals[dayStr] ?? 0;
            final label = isLoading ? '–' : _fmt(hours);

            final textColor = isSelected
                ? colorScheme.primary
                : isFuture
                    ? colorScheme.onSurface.withValues(alpha: 0.3)
                    : colorScheme.onSurfaceVariant;

            return Expanded(
              child: InkWell(
                onTap: isFuture ? null : () => onDayTap(day),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _dayAbbrs[i],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: textColor,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }),
          // Week total column
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Week',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  isLoading ? '–' : _fmt(weekTotal),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
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

class _DailyProgressBar extends StatelessWidget {
  static const double _goal = 8.0;

  final List entries;

  const _DailyProgressBar({required this.entries});

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
    final total =
        entries.fold<double>(0, (sum, e) => sum + (e.hours as double));
    final isOver = total > _goal;
    final progress = (total / _goal).clamp(0.0, 1.0);
    final overflow = total - _goal;

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
              Text(
                isOver
                    ? '+${_fmt(overflow)} over goal'
                    : '${_fmt(_goal - total)} remaining',
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
                // Overflow pulse marker at the 8h boundary
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
  final ProjectCategory category;
  final int entryCount;
  final double totalHours;

  const _ProjectGroupHeader({
    required this.projectName,
    required this.category,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: category.tint,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              category.code,
              style: TextStyle(
                fontFamily: 'Courier New',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: category.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              projectName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HarvestTokens.text,
              ),
            ),
          ),
          Text(
            _fmt(totalHours),
            style: TextStyle(
              fontFamily: 'Courier New',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: category.color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '· $entryCount ${entryCount == 1 ? 'entry' : 'entries'}',
            style: const TextStyle(fontSize: 11, color: HarvestTokens.text3),
          ),
        ],
      ),
    );
  }
}
