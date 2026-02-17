import 'dart:math';
import 'package:flutter/material.dart';

/// Animated wave visualization
class WaveVisualization extends StatefulWidget {
  final double waveHeight;

  const WaveVisualization({super.key, required this.waveHeight});

  @override
  State<WaveVisualization> createState() => _WaveVisualizationState();
}

class _WaveVisualizationState extends State<WaveVisualization>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _waveColor {
    if (widget.waveHeight >= 3) return const Color(0xFFEF4444);
    if (widget.waveHeight >= 2) return const Color(0xFFF97316);
    if (widget.waveHeight >= 1) return const Color(0xFF3B82F6);
    return const Color(0xFF22C55E);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      height: 80,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer, // Adaptive background
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Animated waves
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                size: const Size(double.infinity, 80),
                painter: _WavePainter(
                  animationValue: _controller.value,
                  waveHeight: widget.waveHeight,
                  waveColor: _waveColor,
                  personColor: colorScheme.onSurface, // Adaptive person color
                ),
              );
            },
          ),
          // Height label
          Positioned(
            right: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _waveColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _waveColor, width: 1),
              ),
              child: Text(
                '${widget.waveHeight.toStringAsFixed(1)}m',
                style: TextStyle(
                  color: _waveColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double animationValue;
  final double waveHeight;
  final Color waveColor;
  final Color personColor;

  _WavePainter({
    required this.animationValue,
    required this.waveHeight,
    required this.waveColor,
    required this.personColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Scale wave amplitude based on actual wave height (0-4m range)
    final amplitude = (waveHeight / 4).clamp(0.1, 1.0) * 20;
    final frequency = 2 * pi / size.width * 2;
    final phase = animationValue * 2 * pi;

    // Draw multiple wave layers
    for (int layer = 0; layer < 3; layer++) {
      final layerPhase = phase + layer * 0.5;
      final layerAmplitude = amplitude * (1 - layer * 0.2);
      final opacity = 0.8 - layer * 0.25;

      final path = Path();
      path.moveTo(0, size.height);

      for (double x = 0; x <= size.width; x++) {
        final y = size.height * 0.6 +
            sin(x * frequency + layerPhase) * layerAmplitude +
            sin(x * frequency * 0.5 + layerPhase * 1.3) * layerAmplitude * 0.5;
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.close();

      final gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          waveColor.withValues(alpha: opacity),
          waveColor.withValues(alpha: opacity * 0.3),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

      canvas.drawPath(path, Paint()..shader = gradient);

      // Draw "man for scale" on the first layer
      if (layer == 0) {
        _drawStandingMan(canvas, size, frequency, layerPhase, layerAmplitude);
      }
    }
  }

  void _drawStandingMan(Canvas canvas, Size size, double frequency, double phase, double amplitude) {
    final x = size.width * 0.3; // Position at 30% of width
    final surfaceY = size.height * 0.6 +
        sin(x * frequency + phase) * amplitude +
        sin(x * frequency * 0.5 + phase * 1.3) * amplitude * 0.5;

    final personPaint = Paint()
      ..color = personColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;

    // SCALE CALCULATION:
    // Our wave amplitude is (waveHeight / 4) * 20.
    // If waveHeight = 2m, amplitude = 10px. 
    // This implies 1m height = 10px in our coordinate system.
    // A 1.8m man = 18px tall.
    const personHeight = 18.0;
    const legHeight = 8.0;
    const bodyHeight = 10.0;
    const headRadius = 2.5;

    // We draw him standing "on" the water
    final personBottom = surfaceY;

    // Legs
    final legsPath = Path();
    legsPath.moveTo(x - 1.5, personBottom);
    legsPath.lineTo(x - 0.5, personBottom - legHeight);
    legsPath.lineTo(x + 0.5, personBottom - legHeight);
    legsPath.lineTo(x + 1.5, personBottom);
    legsPath.close();
    canvas.drawPath(legsPath, personPaint);

    // Body
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x - 2.5, personBottom - legHeight - 6, 5, 8),
        const Radius.circular(2),
      ),
      personPaint,
    );

    // Head
    canvas.drawCircle(Offset(x, personBottom - legHeight - 8 - headRadius), headRadius, personPaint);

    // Arms
    final armPaint = Paint()
      ..color = personColor.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    
    // Slight wave-balanced pose
    final balance = sin(animationValue * 2 * pi) * 2.0;
    canvas.drawLine(
      Offset(x - 2.5, personBottom - legHeight - 5),
      Offset(x - 5, personBottom - legHeight - 2 + balance),
      armPaint,
    );
    canvas.drawLine(
      Offset(x + 2.5, personBottom - legHeight - 5),
      Offset(x + 5, personBottom - legHeight - 2 - balance),
      armPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.waveHeight != waveHeight ||
        oldDelegate.personColor != personColor;
  }
}
