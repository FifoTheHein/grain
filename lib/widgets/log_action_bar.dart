import 'package:flutter/material.dart';

import '../theme/harvest_tokens.dart';

/// The bar pinned under Log Time's scroll area: a primary button that says
/// exactly what will be sent ("Log 1h 45m" over "NWR001 · Development ·
/// today"), and a compact ▶ that starts a timer instead.
///
/// Stateless — the screen decides the labels and what is enabled. Covered by
/// `test/log_action_bar_test.dart`.
class LogActionBar extends StatelessWidget {
  /// "Log 1h 45m"; ignored while [disabledReason] is set.
  final String title;

  /// "NWR001 · Development · today", or the clock range in Start & End.
  final String subtitle;

  /// When set, the log button is disabled and shows this instead of
  /// [subtitle] — "Set a duration first".
  final String? disabledReason;

  final bool submitting;
  final VoidCallback onLog;

  /// A tap on the disabled button — lets the screen answer it, e.g. by
  /// showing why nothing happened. The button still looks and reads disabled.
  final VoidCallback? onDisabledTap;

  /// Null disables the timer button.
  final VoidCallback? onStartTimer;
  final String timerTooltip;

  const LogActionBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onLog,
    required this.onStartTimer,
    required this.timerTooltip,
    this.disabledReason,
    this.onDisabledTap,
    this.submitting = false,
  });

  bool get _canLog => disabledReason == null && !submitting;

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final enabled = _canLog;
    final fg = enabled ? palette.onBrand : palette.text3;
    final line1 = submitting
        ? 'Logging…'
        : disabledReason != null
            ? 'Log time'
            : title;
    final line2 = disabledReason ?? subtitle;

    return Material(
      color: palette.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.divider)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Semantics(
                  button: true,
                  enabled: enabled,
                  label: '$line1, $line2',
                  excludeSemantics: true,
                  child: Material(
                    key: const ValueKey('log-button'),
                    color: enabled ? palette.brand : palette.surface3,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: enabled
                          ? onLog
                          : submitting
                              ? null
                              : onDisabledTap,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (submitting)
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: fg),
                                  )
                                else
                                  Icon(Icons.check, size: 18, color: fg),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    line1,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: fg,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              line2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: fg.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: timerTooltip,
                child: SizedBox(
                  width: 54,
                  child: OutlinedButton(
                    key: const ValueKey('timer-button'),
                    onPressed: submitting ? null : onStartTimer,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      side: BorderSide(color: palette.borderStrong),
                      foregroundColor: palette.text2,
                    ),
                    child: Semantics(
                      label: timerTooltip,
                      child: const Icon(Icons.play_arrow, size: 24),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
