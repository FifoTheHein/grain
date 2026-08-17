import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/time_entry.dart';
import '../providers/ado_instance_provider.dart';
import '../services/ado_service.dart';
import '../theme/harvest_tokens.dart';

/// Adds a time entry's hours to its ADO work item's Completed Work, on demand.
///
/// The automatic paths (logging a duration, editing an entry) know how much of
/// an entry they have already pushed, so they can send a delta. A timed entry
/// has no such history — nothing was pushed when it started — so this asks
/// rather than guesses, and shows the before and after so the decision is
/// informed. Returns true when a value was written.
Future<bool> showCompletedWorkSync(BuildContext context, TimeEntry entry) async {
  final ref = entry.externalReference;
  if (ref == null) {
    _toast(context, 'This entry is not linked to a work item');
    return false;
  }

  final instances = context.read<AdoInstanceProvider>().instances;
  final permalink = ref.permalink ?? '';
  AdoInstance? instance;
  for (final candidate in instances) {
    if (candidate.matchesPermalink(permalink)) {
      instance = candidate;
      break;
    }
  }
  if (instance == null || instance.pat == null || instance.pat!.isEmpty) {
    _toast(context, 'No Azure DevOps instance with a PAT matches this entry');
    return false;
  }

  final adoService = context.read<AdoService>();
  final workItemId = AdoService.parseWorkItemId(ref.id);

  final current = await adoService.fetchCompletedWork(instance, workItemId);
  if (!context.mounted) return false;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Add to Completed Work · #$workItemId'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Adds this entry\'s ${_hours(entry.hours)} to the work item.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          _BeforeAfter(current: current, add: entry.hours),
          const SizedBox(height: 12),
          Text(
            current == null
                ? 'Could not read the current value — it will be treated as 0.'
                : 'Only do this if this entry\'s time has not been added '
                    'already. Timed entries are never added automatically; '
                    'entries logged as a duration already were.',
            style: TextStyle(
              fontSize: 11,
              color: current == null
                  ? HarvestTokens.warn
                  : HarvestTokens.of(ctx).text3,
              height: 1.4,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return false;

  try {
    await adoService.addCompletedWork(instance, workItemId, entry.hours);
    if (context.mounted) {
      _toast(context, 'Added ${_hours(entry.hours)} to #$workItemId',
          color: HarvestTokens.success);
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      _toast(context, 'Could not update Completed Work: $e',
          color: HarvestTokens.error);
    }
    return false;
  }
}

/// True when this entry could be pushed to ADO — linked to a work item, with a
/// configured instance, and the Completed Work feature left switched on.
Future<bool> canSyncCompletedWork(
    BuildContext context, TimeEntry entry) async {
  if (entry.externalReference == null) return false;
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool('ado_update_completed_work') ?? true)) return false;
  if (!context.mounted) return false;
  final permalink = entry.externalReference!.permalink ?? '';
  return context
      .read<AdoInstanceProvider>()
      .instances
      .any((i) => i.matchesPermalink(permalink) && (i.pat?.isNotEmpty ?? false));
}

String _hours(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

void _toast(BuildContext context, String message, {Color? color}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: color),
  );
}

class _BeforeAfter extends StatelessWidget {
  final double? current;
  final double add;

  const _BeforeAfter({required this.current, required this.add});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final before = current ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            current == null ? '?' : _hours(before),
            style: TextStyle(fontSize: 14, color: palette.text2),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(Icons.arrow_forward, size: 14, color: palette.text4),
          ),
          Text(
            _hours(before + add),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: palette.brand,
            ),
          ),
        ],
      ),
    );
  }
}
