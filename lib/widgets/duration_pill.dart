import 'package:flutter/material.dart';
import '../theme/harvest_tokens.dart';

class DurationPill extends StatelessWidget {
  final double hours;
  final double size;
  final bool running;

  const DurationPill({
    super.key,
    required this.hours,
    this.size = 44,
    this.running = false,
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
    final label = _label();
    final raw = label.replaceAll('\n', '');
    final fontSize = raw.length > 4 ? 11.0 : raw.length > 2 ? 12.0 : 13.0;

    final pill = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? HarvestTokens.brand : HarvestTokens.brandTint,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: running ? Colors.white : HarvestTokens.brand600,
          height: 1.1,
        ),
      ),
    );

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
              color: HarvestTokens.brand,
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: const Icon(
              Icons.play_arrow,
              size: 9,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
