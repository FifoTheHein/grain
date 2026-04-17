import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;
import '../models/ado_work_item.dart';
import '../theme/harvest_tokens.dart';

class WorkItemChip extends StatelessWidget {
  final String workItemId;
  final AdoWorkItem? cached;
  final bool isLoading;
  final String? permalink;

  const WorkItemChip({
    super.key,
    required this.workItemId,
    this.cached,
    this.isLoading = false,
    this.permalink,
  });

  Color _stateColor(String state) {
    final s = state.toLowerCase();
    if (s.contains('done') || s.contains('closed') || s.contains('resolved')) {
      return HarvestTokens.stateDone;
    }
    if (s.contains('active') ||
        s.contains('progress') ||
        s.contains('committed')) {
      return HarvestTokens.stateActive;
    }
    if (s.contains('removed') || s.contains('cut')) {
      return HarvestTokens.stateRemoved;
    }
    return HarvestTokens.stateNew;
  }

  bool get _canOpen => permalink != null && permalink!.trim().isNotEmpty;

  void _open() {
    if (!_canOpen) return;
    web.window.open(permalink!, '_blank');
  }

  String? _initials(String? name) {
    if (name == null || name.isEmpty) return null;
    return name.trim().split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: HarvestTokens.surface2,
          border: Border.all(color: HarvestTokens.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: HarvestTokens.text4,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Looking up work item…',
              style: TextStyle(fontSize: 12, color: HarvestTokens.text3),
            ),
          ],
        ),
      );
    }

    if (cached == null) {
      return GestureDetector(
        onTap: _open,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.open_in_new, size: 13, color: HarvestTokens.brand600),
            const SizedBox(width: 6),
            Text(
              'ADO #$workItemId',
              style: TextStyle(
                fontSize: 12,
                color: HarvestTokens.brand600,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      );
    }

    final sColor = _stateColor(cached!.state);
    final initials = _initials(cached!.createdByName);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _canOpen ? _open : null,
        child: Container(
          decoration: BoxDecoration(
            color: HarvestTokens.surface2,
            border: Border.all(color: HarvestTokens.border),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.hardEdge,
          child: IntrinsicHeight(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 3, color: sColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(13, 8, 12, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cached!.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            '#$workItemId',
                            style: TextStyle(
                              fontFamily: 'Courier New',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: sColor,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text('·',
                              style: TextStyle(
                                  fontSize: 11, color: HarvestTokens.text4)),
                          const SizedBox(width: 4),
                          Text(
                            cached!.state,
                            style: TextStyle(
                              fontSize: 11,
                              color: sColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (cached!.workItemType != null) ...[
                            const SizedBox(width: 4),
                            Text('·',
                                style: TextStyle(
                                    fontSize: 11, color: HarvestTokens.text4)),
                            const SizedBox(width: 4),
                            Text(
                              cached!.workItemType!,
                              style: TextStyle(
                                  fontSize: 11, color: HarvestTokens.text3),
                            ),
                          ],
                          const Spacer(),
                          if (cached!.createdByAvatarUrl != null || initials != null) ...[
                            CircleAvatar(
                              radius: 11,
                              backgroundColor: HarvestTokens.brandTint,
                              backgroundImage: cached!.createdByAvatarUrl != null
                                  ? NetworkImage(cached!.createdByAvatarUrl!)
                                  : null,
                              child: cached!.createdByAvatarUrl == null
                                  ? Text(
                                      initials ?? '',
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: HarvestTokens.brand600,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Icon(Icons.open_in_new,
                              size: 12, color: HarvestTokens.text3),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
