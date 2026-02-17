import 'dart:math' as math;
import 'package:flutter/material.dart';

class AnimatedWaveWidget extends StatefulWidget {
  final int count;
  final Color color;
  final double size;
  final double speed;

  const AnimatedWaveWidget({
    super.key,
    required this.count,
    required this.color,
    this.size = 24.0,
    this.speed = 1.0,
  });

  @override
  State<AnimatedWaveWidget> createState() => _AnimatedWaveWidgetState();
}

class _AnimatedWaveWidgetState extends State<AnimatedWaveWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: (2000 / widget.speed).round()),
    )..repeat();
  }

  @override
  void didUpdateWidget(AnimatedWaveWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) {
      _controller.duration = Duration(milliseconds: (2000 / widget.speed).round());
      if (_controller.isAnimating) _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 1.5, // Aspect ratio roughly 3:2
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _WavePainter(
              count: widget.count,
              color: widget.color,
              animationValue: _controller.value,
            ),
          );
        },
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final int count;
  final Color color;
  final double animationValue;

  _WavePainter({
    required this.count,
    required this.color,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final width = size.width;
    final rowHeight = size.height / (count + 1); // Space out waves vertically
    
    for (int i = 0; i < count; i++) {
      final path = Path();
      // Phase shift based on animation value + vertical index (so they don't move in valid unison)
      final phaseShift = (animationValue * 2 * math.pi) + (i * math.pi / 2);
      
      final yOffset = (i + 1) * rowHeight;
      
      path.moveTo(0, yOffset);
      
      for (double x = 0; x <= width; x++) {
        // Sine wave formula: y = A * sin(kx - wt)
        // Amplitude is small (relative to row height)
        const amplitude = 2.0;
        final k = (2 * math.pi) / (width * 0.8); // 1.25 waves per width
        
        final y = yOffset + amplitude * math.sin(k * x - phaseShift);
        path.lineTo(x, y);
      }
      
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
           oldDelegate.count != count ||
           oldDelegate.color != color;
  }
}
