import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
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
        if (permalink.startsWith(inst.baseUrl)) {
          matchingInstance = inst;
          break;
        }
      }
    }

    final adoService = hasAdoRef ? context.watch<AdoService>() : null;
    final workItemId = entry.externalReference?.id ?? '';

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
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  onTap: () {
                    final permalink = entry.externalReference!.permalink;
                    if (permalink != null) {
                      web.window.open(permalink, '_blank');
                    }
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              if (matchingInstance != null && adoService != null)
                WorkItemPreview(
                  isLoading: adoService.isPending(
                      matchingInstance.label, workItemId),
                  workItem:
                      adoService.getCached(matchingInstance.label, workItemId),
                  hasPat: matchingInstance.pat != null,
                  workItemId: workItemId,
                  instance: matchingInstance,
                  showNoPat: false,
                ),
            ],
          ],
        ),
        isThreeLine: (entry.notes != null && entry.notes!.isNotEmpty) ||
            hasAdoRef,
      ),
    );
  }
}
