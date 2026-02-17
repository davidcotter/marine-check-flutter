import 'package:flutter/material.dart';
import 'dart:math' as Math;

class TideGraphic extends StatelessWidget {
  final int percentage;
  final Color color;
  final double width;
  final double height;

  const TideGraphic({
    super.key,
    required this.percentage,
    required this.color,
    this.width = 40,
    this.height = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: CustomPaint(
          painter: _WavePainter(
            percentage: percentage / 100.0,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double percentage;
  final Color color;

  _WavePainter({required this.percentage, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final path = Path();
    final yBase = size.height * (1.0 - percentage);
    
    path.moveTo(0, size.height);
    path.lineTo(0, yBase);
    
    // Create a simple wave effect
    for (double x = 0; x <= size.width; x++) {
      final y = yBase + 2 * Math.sin((x / size.width) * 2 * Math.pi);
      path.lineTo(x, y);
    }
    
    path.lineTo(size.width, size.height);
    path.close();
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
