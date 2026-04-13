import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../services/ado_service.dart';

class TimeEntryCard extends StatelessWidget {
  final TimeEntry entry;

  const TimeEntryCard({super.key, required this.entry});

  Color _stateColor(BuildContext context, String state) {
    final s = state.toLowerCase();
    if (s.contains('done') || s.contains('closed') || s.contains('resolved')) {
      return Colors.green;
    }
    if (s.contains('active') ||
        s.contains('in progress') ||
        s.contains('committed')) {
      return Colors.blue;
    }
    if (s.contains('removed') || s.contains('cut')) {
      return Colors.grey;
    }
    return Theme.of(context).colorScheme.secondary;
  }

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

    AdoWorkItem? workItem;
    if (hasAdoRef) {
      final adoService = context.watch<AdoService>();
      final instances = context.watch<AdoInstanceProvider>().instances;
      final permalink = entry.externalReference!.permalink ?? '';
      for (final instance in instances) {
        if (permalink.startsWith(instance.baseUrl)) {
          workItem =
              adoService.getCached(instance.label, entry.externalReference!.id);
          break;
        }
      }
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
                        'ADO #${entry.externalReference!.id}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              decoration: TextDecoration.underline,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              if (workItem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 3, right: 6),
                        decoration: BoxDecoration(
                          color: _stateColor(context, workItem.state),
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${workItem.title}  ·  ${workItem.state}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
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
