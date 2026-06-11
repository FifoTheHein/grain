import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/harvest_tokens.dart';

class WeeklyProgressRing extends StatelessWidget {
  final double hours;
  final double goal;
  final double size;
  final double stroke;
  final bool showCaption;

  const WeeklyProgressRing({
    super.key,
    required this.hours,
    this.goal = 40,
    this.size = 96,
    this.stroke = 9,
    this.showCaption = true,
  });

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final pct = (hours / goal).clamp(0.0, 1.0);
    final isOver = hours > goal;
    final ringColor = isOver ? HarvestTokens.warn : HarvestTokens.brand;
    final goalLabel = 'of ${goal % 1 == 0 ? goal.toInt() : goal}h';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: pct),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      builder: (ctx, animPct, _) {
        final ring = SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              pct: animPct,
              stroke: stroke,
              ringColor: ringColor,
              trackColor: palette.surface3,
            ),
            // Over-goal: center is empty — label shown beside the ring
            child: isOver
                ? null
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _fmt(hours),
                          style: TextStyle(
                            fontFamily: 'Courier New',
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontSize: _labelFontSize(_fmt(hours)),
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.6,
                            color: palette.text,
                            height: 1,
                          ),
                        ),
                        if (size >= 72) ...[
                          const SizedBox(height: 2),
                          Text(
                            goalLabel,
                            style: TextStyle(
                              fontSize: 10,
                              color: palette.text3,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        );

        // Over-goal: ring + label side-by-side
        final ringRow = isOver
            ? Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ring,
                  const SizedBox(width: 10),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmt(hours),
                        style: TextStyle(
                          fontFamily: 'Courier New',
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontSize: _labelFontSize(_fmt(hours)),
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.6,
                          color: HarvestTokens.warn,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        goalLabel,
                        style: TextStyle(
                          fontSize: 10,
                          color: palette.text3,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              )
            : ring;

        if (!showCaption) return ringRow;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ringRow,
            const SizedBox(height: 10),
            _Caption(hours: hours, goal: goal, isOver: isOver),
          ],
        );
      },
    );
  }

  double _labelFontSize(String label) {
    if (label.length <= 2) return size >= 96 ? 22 : 18;
    if (label.length <= 4) return size >= 96 ? 20 : 16;
    return size >= 96 ? 16 : 13;
  }

  static String _fmt(double h) {
    final total = (h * 60).round();
    final hh = total ~/ 60;
    final mm = total % 60;
    if (hh == 0 && mm == 0) return '–';
    if (hh == 0) return '${mm}m';
    if (mm == 0) return '${hh}h';
    return '${hh}h ${mm}m';
  }
}

class _Caption extends StatelessWidget {
  final double hours;
  final double goal;
  final bool isOver;

  const _Caption({
    required this.hours,
    required this.goal,
    required this.isOver,
  });

  String _fmt(double h) {
    final total = (h * 60).round();
    final hh = total ~/ 60;
    final mm = total % 60;
    if (hh == 0 && mm == 0) return '–';
    if (hh == 0) return '${mm}m';
    if (mm == 0) return '${hh}h';
    return '${hh}h ${mm}m';
  }

  @override
  Widget build(BuildContext context) {
    final palette = HarvestTokens.of(context);
    final String helperText;
    if (isOver) {
      helperText = '+${_fmt(hours - goal)} over';
    } else if (hours >= goal) {
      helperText = 'Goal met';
    } else {
      helperText = '${_fmt(goal - hours)} to go';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'THIS WEEK',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: palette.text3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          helperText,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: isOver ? HarvestTokens.warn : palette.text2,
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final double pct;
  final double stroke;
  final Color ringColor;
  final Color trackColor;

  _RingPainter({
    required this.pct,
    required this.stroke,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (pct > 0) {
      final progress = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = ringColor;
      canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * pct, false, progress);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.pct != pct || old.ringColor != ringColor;
}
