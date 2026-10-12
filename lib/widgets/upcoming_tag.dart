import 'package:flutter/material.dart';

import '../theme/harvest_tokens.dart';
import 'dashed_border.dart';

/// The small dashed UPCOMING label beside a future date, on Recent's header
/// and Log Time's "logging ahead" line.
class UpcomingTag extends StatelessWidget {
  const UpcomingTag({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    return DashedBorder(
      color: palette.text3,
      strokeWidth: 1,
      radius: 4,
      dash: 3,
      gap: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          'UPCOMING',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: palette.text3,
          ),
        ),
      ),
    );
  }
}
