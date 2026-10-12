import 'package:flutter/material.dart';
import '../theme/harvest_tokens.dart';
import 'dashed_border.dart';

class DurationPill extends StatelessWidget {
  final double hours;
  final double size;
  final bool running;

  /// Logged ahead, on a day not yet reached: an empty dashed ring instead of
  /// the filled tint.
  final bool planned;

  const DurationPill({
    super.key,
    required this.hours,
    this.size = 44,
    this.running = false,
    this.planned = false,
  });

  String _label() {
    final total = (hours * 60).round();
    final h = total ~/ 60;
    final m = total % 60;
    if (h == 0 && m == 0) return '–';
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h\n${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final label = _label();
    final raw = label.replaceAll('\n', '');
    final fontSize = raw.length > 4 ? 11.0 : raw.length > 2 ? 12.0 : 13.0;

    final pill = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running
            ? palette.brand
            : planned
                ? Colors.transparent
                : palette.brandTint,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: running
              ? palette.onBrand
              : planned
                  ? palette.text2
                  : palette.brand600,
          height: 1.1,
        ),
      ),
    );

    if (planned && !running) {
      return DashedBorder(
        key: const ValueKey('planned-pill'),
        color: palette.text3,
        circle: true,
        child: pill,
      );
    }

    if (!running) return pill;

    // Clip.none lets the badge render outside the pill's bounding box.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        pill,
        Positioned(
          right: -3,
          bottom: -3,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.brand,
              border: Border.all(color: palette.onBrand, width: 1.5),
            ),
            child: Icon(
              Icons.play_arrow,
              size: 9,
              color: palette.onBrand,
            ),
          ),
        ),
      ],
    );
  }
}
