import 'package:flutter/material.dart';
import '../theme/harvest_tokens.dart';

class DurationPill extends StatelessWidget {
  final double hours;
  final double size;
  final bool active;

  const DurationPill({
    super.key,
    required this.hours,
    this.size = 44,
    this.active = false,
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
    // font size: 13px ≤2 chars, 12px 3-4 chars, 11px 5+
    final raw = label.replaceAll('\n', '');
    final fontSize = raw.length > 4 ? 11.0 : raw.length > 2 ? 12.0 : 13.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? HarvestTokens.brand : HarvestTokens.brandTint,
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Courier New',
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : HarvestTokens.brand600,
          height: 1.1,
        ),
      ),
    );
  }
}
