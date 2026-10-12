import 'dart:async';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/entry_display.dart';
import '../models/future_days.dart';
import '../models/time_entry.dart';
import '../utils/open_url.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/project_category_provider.dart';
import '../providers/time_entry_provider.dart';
import '../screens/edit_time_screen.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';
import 'completed_work_sync.dart';
import 'duration_pill.dart';
import 'work_item_chip.dart';

class TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;

  const TimeEntryCard({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final hasAdoRef = entry.adoReference != null;

    // Resolve ADO instance for this entry
    AdoInstance? matchingInstance;
    if (hasAdoRef) {
      final instances = context.watch<AdoInstanceProvider>().instances;
      final permalink = entry.adoReference!.permalink ?? '';
      for (final inst in instances) {
        if (inst.matchesPermalink(permalink)) {
          matchingInstance = inst;
          break;
        }
      }
    }

    final adoService = hasAdoRef ? context.watch<AdoService>() : null;
    final rawRefId = entry.adoReference?.id ?? '';
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

    final notesLine = hasAdoRef
        ? workItemNotesLine(entry.notes, workItemId)
        : (entry.notes?.trim().isEmpty ?? true)
            ? null
            : entry.notes!.trim();
    final meetingStart = meetingStartLabel(entry);

    return Card(
      clipBehavior: Clip.antiAlias,
      // The running entry stands out, since it can scroll out of view.
      shape: entry.isRunning
          ? RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              side: BorderSide(color: palette.brand, width: 1.5),
            )
          : null,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => EditTimeScreen(entry: entry)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading: duration pill, counting up while the timer runs
              Builder(builder: (context) {
                if (!entry.isRunning) {
                  return DurationPill(
                    hours: entry.hours,
                    size: 38,
                    planned: isFutureSpentDate(entry.spentDate, DateTime.now()),
                  );
                }
                final provider = context.watch<TimeEntryProvider>();
                return _LiveDurationPill(
                  entry: entry,
                  fetchedAt: provider.fetchedAt,
                );
              }),
              const SizedBox(width: 10),

              // Body
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Head line: project code chip, task, meeting start
                    Row(
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
                        if (meetingStart != null) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: 'Imported meeting',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.event_outlined,
                                    size: 13, color: palette.text3),
                                const SizedBox(width: 3),
                                Text(
                                  meetingStart,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: palette.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),

                    // Notes, one line
                    if (notesLine != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        notesLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.text2,
                          height: 1.35,
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
                          permalink: entry.adoReference!.permalink,
                        )
                      else
                        GestureDetector(
                          onTap: (entry.adoReference!.permalink != null &&
                                  entry.adoReference!.permalink!.isNotEmpty)
                              ? () => openUrl(entry.adoReference!.permalink!)
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new,
                                size: 13,
                                color: palette.brand600,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'ADO #$workItemId',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: palette.brand600,
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

              // Trailing: the one action. Tapping the card itself edits.
              _TimerButton(entry: entry),
            ],
          ),
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
      size: 38,
    );
  }
}

/// Stop for a running entry, Continue for a stopped one.
class _TimerButton extends StatelessWidget {
  final TimeEntry entry;

  const _TimerButton({required this.entry});

  Future<void> _run(
    BuildContext context,
    Future<bool> Function() action, {
    bool offerAdoSync = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<TimeEntryProvider>();
    final ok = await action();
    if (!context.mounted) return;

    // A stopped timer never pushed its hours to ADO, so this is the moment to
    // offer it — with the entry as the provider now has it, hours included.
    final stopped = provider.entries.firstWhereOrNull((e) => e.id == entry.id);
    final canSync =
        ok && offerAdoSync && stopped != null && await canSyncCompletedWork(context, stopped);
    if (!context.mounted) return;

    const visibleFor = Duration(seconds: 15);
    final controller = messenger.showSnackBar(
      SnackBar(
        content: Text(ok
            ? (provider.successMessage ?? 'Done')
            : (provider.error ?? 'Could not reach Harvest')),
        backgroundColor: ok ? HarvestTokens.success : HarvestTokens.error,
        duration: canSync ? visibleFor : const Duration(seconds: 4),
        // Dismissable by hand as well as by timeout, since the action version
        // sits over the content for a while.
        showCloseIcon: canSync,
        closeIconColor: Colors.white,
        action: canSync
            ? SnackBarAction(
                label: 'Sync to ADO',
                textColor: Colors.white,
                onPressed: () => showCompletedWorkSync(context, stopped),
              )
            : null,
      ),
    );

    if (!canSync) return;

    // A SnackBar carrying an action does not time out on its own — Flutter's
    // `SnackBar.persist` defaults to `action != null`, so `duration` is
    // ignored and it waits for a tap. Close it here instead, and only while it
    // is still the one on screen: `close` asserts that it is.
    var open = true;
    unawaited(controller.closed.then((_) => open = false));
    Timer(visibleFor, () {
      if (open) controller.close();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final provider = context.watch<TimeEntryProvider>();
    final busy = provider.isSubmitting;

    if (entry.isRunning) {
      return IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.stop_circle_outlined, size: 20),
        tooltip: 'Stop timer',
        color: palette.brand,
        onPressed: busy
            ? null
            : () => _run(context, () => provider.stopTimer(entry.id),
                offerAdoSync: true),
      );
    }

    // Harvest runs one timer per user, so resuming while another is going
    // would silently stop that one. And it times today: an entry logged
    // ahead has nothing to continue yet.
    final another = provider.runningEntry;
    final future = isFutureSpentDate(entry.spentDate, DateTime.now());
    return IconButton(
      key: const ValueKey('continue-timer'),
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.play_circle_outline, size: 20),
      tooltip: future
          ? 'Timers only run for today'
          : another == null
              ? 'Continue timing this entry'
              : 'Stop the running timer first',
      color: palette.text3,
      onPressed: busy || another != null || future
          ? null
          : () => _run(context, () => provider.restartTimer(entry.id)),
    );
  }
}
