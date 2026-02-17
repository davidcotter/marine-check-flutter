import 'package:flutter/material.dart';
import '../models/marine_data.dart';

/// Tide curve visualization using CustomPainter
class TideCurve extends StatelessWidget {
  final List<HourlyForecast> hours;
  final int selectedHour;
  final List<double> levels;

  const TideCurve({
    super.key,
    required this.hours,
    required this.selectedHour,
    required this.levels,
  });

  @override
  Widget build(BuildContext context) {
    if (levels.isEmpty) {
      return const SizedBox(
        height: 120,
        child: Center(child: Text('No tide data', style: TextStyle(color: Color(0xFF64748B)))),
      );
    }

    final minLevel = levels.reduce((a, b) => a < b ? a : b);
    final maxLevel = levels.reduce((a, b) => a > b ? a : b);

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: CustomPaint(
        size: const Size(double.infinity, 120),
        painter: _TideCurvePainter(
          levels: levels,
          selectedIndex: selectedHour,
          minLevel: minLevel,
          maxLevel: maxLevel,
        ),
      ),
    );
  }
}

class _TideCurvePainter extends CustomPainter {
  final List<double> levels;
  final int selectedIndex;
  final double minLevel;
  final double maxLevel;

  _TideCurvePainter({
    required this.levels,
    required this.selectedIndex,
    required this.minLevel,
    required this.maxLevel,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;

    final paddingX = 30.0;
    final paddingY = 20.0;
    final chartWidth = size.width - paddingX * 2;
    final chartHeight = size.height - paddingY * 2;
    final range = maxLevel - minLevel;
    if (range == 0) return;

    // Draw axis lines
    final axisPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 1;

    canvas.drawLine(
      Offset(paddingX, paddingY),
      Offset(paddingX, size.height - paddingY),
      axisPaint,
    );
    canvas.drawLine(
      Offset(paddingX, size.height - paddingY),
      Offset(size.width - paddingX, size.height - paddingY),
      axisPaint,
    );

    // Calculate points
    final points = <Offset>[];
    for (int i = 0; i < levels.length; i++) {
      final x = paddingX + (i / (levels.length - 1)) * chartWidth;
      final y = paddingY + (1 - (levels[i] - minLevel) / range) * chartHeight;
      points.add(Offset(x, y));
    }

    // Draw gradient fill
    if (points.length >= 2) {
      final fillPath = Path()..moveTo(points.first.dx, size.height - paddingY);
      for (final p in points) {
        fillPath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(points.last.dx, size.height - paddingY);
      fillPath.close();

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF3B82F6).withValues(alpha: 0.3),
          const Color(0xFF3B82F6).withValues(alpha: 0.05),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(fillPath, Paint()..shader = gradient);
    }

    // Draw curve line
    final linePaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final linePath = Path();
    for (int i = 0; i < points.length; i++) {
      if (i == 0) {
        linePath.moveTo(points[i].dx, points[i].dy);
      } else {
        // Use quadratic bezier for smooth curve
        final prev = points[i - 1];
        final curr = points[i];
        final midX = (prev.dx + curr.dx) / 2;
        linePath.quadraticBezierTo(prev.dx, prev.dy, midX, (prev.dy + curr.dy) / 2);
        if (i == points.length - 1) {
          linePath.lineTo(curr.dx, curr.dy);
        }
      }
    }
    canvas.drawPath(linePath, linePaint);

    // Draw selected point
    if (selectedIndex >= 0 && selectedIndex < points.length) {
      final selected = points[selectedIndex];

      // Vertical line
      canvas.drawLine(
        Offset(selected.dx, paddingY),
        Offset(selected.dx, size.height - paddingY),
        Paint()
          ..color = const Color(0xFFF8FAFC).withValues(alpha: 0.3)
          ..strokeWidth = 1,
      );

      // Point
      canvas.drawCircle(
        selected,
        6,
        Paint()..color = const Color(0xFF3B82F6),
      );
      canvas.drawCircle(
        selected,
        4,
        Paint()..color = Colors.white,
      );
    }

    // Draw labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    // Max label
    textPainter.text = TextSpan(
      text: '${maxLevel.toStringAsFixed(1)}m',
      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - paddingX + 4, paddingY - 6));

    // Min label
    textPainter.text = TextSpan(
      text: '${minLevel.toStringAsFixed(1)}m',
      style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - paddingX + 4, size.height - paddingY - 6));
  }

  @override
  bool shouldRepaint(covariant _TideCurvePainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.levels != levels;
  }
}
