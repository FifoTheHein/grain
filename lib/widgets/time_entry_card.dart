import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:web/web.dart' as web;
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../providers/project_category_provider.dart';
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
            // Leading: duration pill
            DurationPill(hours: entry.hours),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HarvestTokens.text,
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: HarvestTokens.text2,
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
                            ? () => web.window
                                .open(entry.externalReference!.permalink!, '_blank')
                            : null,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_new,
                              size: 13,
                              color: (entry.externalReference!.permalink != null &&
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            final p = entry.externalReference!.permalink;
                            if (p != null) web.window.open(p, '_blank');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.open_in_new,
                                    size: 13,
                                    color: HarvestTokens.brand600),
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
                        ),
                      ),
                  ],
                ],
              ),
            ),

            // Trailing: edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 16),
              tooltip: 'Edit entry',
              color: HarvestTokens.text3,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditTimeScreen(entry: entry),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
