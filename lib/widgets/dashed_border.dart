import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// A dashed outline around [child] — Flutter's `Border` only draws solid
/// lines. Marks what is planned rather than done: a selected future day on
/// Recent's week strip, a duration logged ahead, the UPCOMING tag.
///
/// A [circle] outlines the largest circle that fits; otherwise a rounded
/// rectangle with [radius].
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool circle;
  final double dash;
  final double gap;

  const DashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.strokeWidth = 1.5,
    this.radius = 8,
    this.circle = false,
    this.dash = 4,
    this.gap = 3,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedPainter(
        color: color,
        strokeWidth: strokeWidth,
        radius: radius,
        circle: circle,
        dash: dash,
        gap: gap,
      ),
      child: child,
    );
  }
}

class _DashedPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final bool circle;
  final double dash;
  final double gap;

  const _DashedPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.circle,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
        inset, inset, size.width - strokeWidth, size.height - strokeWidth);
    final path = Path();
    if (circle) {
      path.addOval(Rect.fromCircle(
          center: rect.center, radius: rect.shortestSide / 2));
    } else {
      path.addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    for (final PathMetric metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedPainter old) =>
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.radius != radius ||
      old.circle != circle ||
      old.dash != dash ||
      old.gap != gap;
}
