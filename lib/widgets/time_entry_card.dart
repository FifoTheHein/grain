import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/time_entry.dart';
import '../utils/open_url.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../screens/edit_time_screen.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';
import 'duration_pill.dart';
import 'work_item_chip.dart';

class TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;

  const TimeEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final hasAdoRef = entry.externalReference != null;

    // Resolve ADO instance for this entry
    AdoInstance? matchingInstance;
    if (hasAdoRef) {
      final instances = context.watch<AdoInstanceProvider>().instances;
      final permalink = entry.externalReference!.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          matchingInstance = inst;
          break;
        }
      }
    }

    final adoService = hasAdoRef ? context.watch<AdoService>() : null;
    final rawRefId = entry.externalReference?.id ?? '';
    final workItemId =
        rawRefId.isNotEmpty ? AdoService.parseWorkItemId(rawRefId) : '';

    // Self-trigger fetch when card renders without cached data.
    if (matchingInstance != null &&
        matchingInstance.pat != null &&
        adoService != null &&
        adoService.getCached(matchingInstance.label, workItemId) == null &&
        !adoService.isPending(matchingInstance.label, workItemId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        adoService.fetchWorkItem(matchingInstance!, workItemId);
      });
    }

    // Project category for the color chip
    final catProvider = context.watch<ProjectCategoryProvider>();
    final cat = catProvider.categoryFor(
      entry.projectId,
      fallbackCode: entry.projectName
          .split(' ')
          .where((w) => w.isNotEmpty)
          .take(3)
          .map((w) => w[0].toUpperCase())
          .join(),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading: duration pill, counting up while the timer runs
            Builder(builder: (context) {
              if (!entry.isRunning) {
                return DurationPill(hours: entry.hours);
              }
              final provider = context.watch<TimeEntryProvider>();
              return _LiveDurationPill(
                entry: entry,
                fetchedAt: provider.fetchedAt,
              );
            }),
            const SizedBox(width: 12),

            // Body
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row: project code chip + task name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cat.tint,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          cat.code,
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                            color: cat.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.taskName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Notes
                  if (entry.notes != null && entry.notes!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      entry.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.text2,
                        height: 1.45,
                      ),
                    ),
                  ],

                  // ADO chip
                  if (hasAdoRef) ...[
                    const SizedBox(height: 6),
                    if (matchingInstance != null && adoService != null)
                      WorkItemChip(
                        workItemId: workItemId,
                        cached: adoService.getCached(
                            matchingInstance.label, workItemId),
                        isLoading: adoService.isPending(
                            matchingInstance.label, workItemId),
                        permalink: entry.externalReference!.permalink,
                      )
                    else
                      GestureDetector(
                        onTap: (entry.externalReference!.permalink != null &&
                                entry.externalReference!.permalink!.isNotEmpty)
                            ? () => openUrl(entry.externalReference!.permalink!)
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new,
                              size: 13,
                              color: HarvestTokens.brand600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'ADO #$workItemId',
                              style: const TextStyle(
                                fontSize: 12,
                                color: HarvestTokens.brand600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Trailing: timer control + edit button
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TimerButton(entry: entry),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  tooltip: 'Edit entry',
                  color: palette.text3,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EditTimeScreen(entry: entry),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Duration pill that ticks while the entry's timer runs. Rebuilds once a
/// second rather than watching a global ticker, so only the running card
/// repaints.
class _LiveDurationPill extends StatefulWidget {
  final TimeEntry entry;
  final DateTime fetchedAt;

  const _LiveDurationPill({required this.entry, required this.fetchedAt});

  @override
  State<_LiveDurationPill> createState() => _LiveDurationPillState();
}

class _LiveDurationPillState extends State<_LiveDurationPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DurationPill(
      hours: widget.entry.liveHours(widget.fetchedAt, DateTime.now()),
      running: true,
    );
  }
}

/// Stop for a running entry, Continue for a stopped one.
class _TimerButton extends StatelessWidget {
  final TimeEntry entry;

  const _TimerButton({required this.entry});

  Future<void> _run(BuildContext context, Future<bool> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<TimeEntryProvider>();
    final ok = await action();
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? (provider.successMessage ?? 'Done')
            : (provider.error ?? 'Could not reach Harvest')),
        backgroundColor: ok ? HarvestTokens.success : HarvestTokens.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = context.watch<TimeEntryProvider>();
    final busy = provider.isSubmitting;

    if (entry.isRunning) {
      return IconButton(
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        tooltip: 'Stop timer',
        color: HarvestTokens.brand,
        onPressed: busy
            ? null
            : () => _run(context, () => provider.stopTimer(entry.id)),
      );
    }

    // Harvest runs one timer per user, so resuming while another is going
    // would silently stop that one.
    final another = provider.runningEntry;
    return IconButton(
      icon: const Icon(Icons.play_circle_outline, size: 18),
      tooltip: another == null
          ? 'Continue timing this entry'
          : 'Stop the running timer first',
      color: palette.text3,
      onPressed: busy || another != null
          ? null
          : () => _run(context, () => provider.restartTimer(entry.id)),
    );
  }
}
