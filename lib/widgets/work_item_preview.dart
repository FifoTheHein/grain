import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../models/ado_work_item.dart';
import '../models/time_entry.dart';

class WorkItemPreview extends StatelessWidget {
  final bool isLoading;
  final AdoWorkItem? workItem;
  final bool hasPat;
  final String workItemId;
  final AdoInstance instance;

  /// When false the "Configure a PAT in Settings" hint is suppressed.
  /// Set to false in compact contexts like entry cards.
  final bool showNoPat;

  /// When provided the card opens this URL on tap.
  final String? permalink;

  const WorkItemPreview({
    super.key,
    required this.isLoading,
    required this.workItem,
    required this.hasPat,
    required this.workItemId,
    required this.instance,
    this.showNoPat = true,
    this.permalink,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasPat) {
      if (!showNoPat) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'Configure a PAT in Settings to see work item details.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    if (workItemId.isEmpty) return const SizedBox.shrink();

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Looking up work item...'),
          ],
        ),
      );
    }

    if (workItem != null) {
      final stateColor = _stateColor(context, workItem!.state);
      final url = permalink ?? instance.permalinkFor(workItemId);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: () => web.window.open(url, '_blank'),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: stateColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          workItem!.title,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '#$workItemId · ${workItem!.state}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: stateColor,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Fallback: show permalink as a plain link
    final url = permalink ?? instance.permalinkFor(workItemId);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => web.window.open(url, '_blank'),
        child: Text(
          'ADO #$workItemId',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
        ),
      ),
    );
  }

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
}
