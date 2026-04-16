import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../screens/edit_time_screen.dart';
import '../services/ado_service.dart';
import 'work_item_preview.dart';

class TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;

  const TimeEntryCard({super.key, required this.entry});

  String _formatDuration(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final hasAdoRef = entry.externalReference != null;
    final durationLabel = _formatDuration(entry.hours);

    // Find the matching ADO instance for this entry's permalink
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

    // Self-trigger fetch when the card renders without cached data.
    // Handles race where AdoInstanceProvider hasn't finished loading
    // from SharedPreferences when the screen-level prefetch ran.
    if (matchingInstance != null &&
        matchingInstance.pat != null &&
        adoService != null &&
        adoService.getCached(matchingInstance.label, workItemId) == null &&
        !adoService.isPending(matchingInstance.label, workItemId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        adoService.fetchWorkItem(matchingInstance!, workItemId);
      });
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            durationLabel,
            style: TextStyle(
              fontSize: durationLabel.length > 4 ? 10 : 12,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(
          '${entry.projectName} — ${entry.taskName}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.spentDate),
            if (entry.notes != null && entry.notes!.isNotEmpty)
              Text(
                entry.notes!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (hasAdoRef) ...[
              if (matchingInstance != null && adoService != null)
                WorkItemPreview(
                  isLoading: adoService.isPending(
                      matchingInstance.label, workItemId),
                  workItem: adoService.getCached(
                      matchingInstance.label, workItemId),
                  hasPat: matchingInstance.pat != null,
                  workItemId: workItemId,
                  instance: matchingInstance,
                  permalink: entry.externalReference!.permalink,
                  showNoPat: false,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: InkWell(
                    onTap: () {
                      final p = entry.externalReference!.permalink;
                      if (p != null) web.window.open(p, '_blank');
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'ADO #$workItemId',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                decoration: TextDecoration.underline,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
        isThreeLine: (entry.notes != null && entry.notes!.isNotEmpty) ||
            hasAdoRef,
        trailing: IconButton(
          icon: const Icon(Icons.edit_outlined),
          tooltip: 'Edit entry',
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => EditTimeScreen(entry: entry),
            ),
          ),
        ),
      ),
    );
  }
}
