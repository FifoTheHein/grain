import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/time_entry.dart';

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
            if (hasAdoRef)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: InkWell(
                  onTap: () {
                    final permalink = entry.externalReference!.permalink;
                    if (permalink != null) {
                      launchUrl(Uri.parse(permalink),
                          mode: LaunchMode.externalApplication);
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
          ],
        ),
        isThreeLine: (entry.notes != null && entry.notes!.isNotEmpty) ||
            hasAdoRef,
      ),
    );
  }
}
