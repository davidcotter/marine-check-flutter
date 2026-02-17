import 'dart:math';
import 'package:flutter/material.dart';

/// Animated weather background based on WMO weather codes.
/// Renders sun rays, drifting clouds, rain drops, snow flakes, or lightning.
/// Cloud density is driven by actual cloud_cover % from the API.
class WeatherBackground extends StatefulWidget {
  final int wmoCode;
  final int cloudCover; // 0-100%
  final Widget child;
  final BorderRadius borderRadius;

  const WeatherBackground({
    super.key,
    required this.wmoCode,
    required this.child,
    this.cloudCover = 50,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  @override
  State<WeatherBackground> createState() => _WeatherBackgroundState();
}

class _WeatherBackgroundState extends State<WeatherBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late AnimationController _slowController;

  @override
  void initState() {
    super.initState();
    // Rain/snow particles — moderate speed
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    // Clouds and ambient drift — very slow, dreamy pace
    _slowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    _slowController.dispose();
    super.dispose();
  }

  _WeatherType get _weatherType {
    final code = widget.wmoCode;
    if (code == 0) return _WeatherType.clear;
    if (code <= 3) return _WeatherType.partlyCloudy;
    if (code <= 48) return _WeatherType.foggy;
    if (code <= 67) return _WeatherType.rainy;
    if (code <= 77) return _WeatherType.snowy;
    if (code <= 82) return _WeatherType.rainy;
    if (code <= 86) return _WeatherType.snowy;
    return _WeatherType.stormy;
  }

  List<Color> get _gradientColors {
    switch (_weatherType) {
      case _WeatherType.clear:
        return [
          const Color(0xFF1E3A5F),
          const Color(0xFF0F2847),
          const Color(0xFF1A3055),
        ];
      case _WeatherType.partlyCloudy:
        return [
          const Color(0xFF1E3050),
          const Color(0xFF253548),
          const Color(0xFF1A2D45),
        ];
      case _WeatherType.foggy:
        return [
          const Color(0xFF2A3040),
          const Color(0xFF1F2535),
          const Color(0xFF252B3B),
        ];
      case _WeatherType.rainy:
        return [
          const Color(0xFF1A2535),
          const Color(0xFF15202E),
          const Color(0xFF1C2638),
        ];
      case _WeatherType.snowy:
        return [
          const Color(0xFF2A3248),
          const Color(0xFF1F2840),
          const Color(0xFF253050),
        ];
      case _WeatherType.stormy:
        return [
          const Color(0xFF151820),
          const Color(0xFF1A1D28),
          const Color(0xFF12151C),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: widget.borderRadius,
          child: Stack(
            children: [
              // Gradient base — sized explicitly
              SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight.isFinite ? constraints.maxHeight : null,
                child: AnimatedBuilder(
                  animation: _slowController,
                  builder: (context, _) {
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(
                            -1 + _slowController.value * 0.3,
                            -1,
                          ),
                          end: Alignment(
                            1 - _slowController.value * 0.3,
                            1,
                          ),
                          colors: _gradientColors,
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Weather particles — sized explicitly
              SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight.isFinite ? constraints.maxHeight : null,
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _WeatherPainter(
                        type: _weatherType,
                        progress: _controller.value,
                        slowProgress: _slowController.value,
                        cloudCover: widget.cloudCover,
                      ),
                    );
                  },
                ),
              ),
              // Content on top
              widget.child,
            ],
          ),
        );
      },
    );
  }
}

enum _WeatherType { clear, partlyCloudy, foggy, rainy, snowy, stormy }

class _WeatherPainter extends CustomPainter {
  final _WeatherType type;
  final double progress;
  final double slowProgress;
  final int cloudCover;

  _WeatherPainter({
    required this.type,
    required this.progress,
    required this.slowProgress,
    required this.cloudCover,
  });

  // Cloud cover fraction 0.0 - 1.0
  double get _cloudFraction => cloudCover.clamp(0, 100) / 100.0;

  @override
  void paint(Canvas canvas, Size size) {
    switch (type) {
      case _WeatherType.clear:
        _paintSunScene(canvas, size);
        // Even on "clear" days, if cloud cover > 10% show light clouds
        if (_cloudFraction > 0.1) {
          _paintClouds(canvas, size);
        }
        break;
      case _WeatherType.partlyCloudy:
        _paintSunScene(canvas, size);
        _paintClouds(canvas, size);
        break;
      case _WeatherType.foggy:
        _paintFog(canvas, size);
        break;
      case _WeatherType.rainy:
        _paintClouds(canvas, size);
        _paintRain(canvas, size);
        break;
      case _WeatherType.snowy:
        _paintClouds(canvas, size);
        _paintSnow(canvas, size);
        break;
      case _WeatherType.stormy:
        _paintClouds(canvas, size);
        _paintRain(canvas, size);
        _paintLightning(canvas, size);
        break;
    }
  }

  void _paintSunScene(Canvas canvas, Size size) {
    final sunX = size.width * 0.82;
    final sunY = size.height * 0.2;
    final glowRadius = size.width * 0.25 + sin(slowProgress * 2 * pi) * 4;

    // Outer glow — dimmer when cloudy
    final sunIntensity = 1.0 - (_cloudFraction * 0.7);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.fromRGBO(251, 191, 36, 0.08 * sunIntensity + sin(slowProgress * 2 * pi) * 0.02),
          Color.fromRGBO(245, 158, 11, 0.03 * sunIntensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: Offset(sunX, sunY), radius: glowRadius));
    canvas.drawCircle(Offset(sunX, sunY), glowRadius, glowPaint);

    // Sun rays
    final rayPaint = Paint()
      ..color = Color.fromRGBO(251, 191, 36, 0.06 * sunIntensity)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi + slowProgress * 2 * pi * 0.3;
      final innerR = size.width * 0.06;
      final outerR = size.width * 0.12 + sin(progress * 2 * pi + i) * 3;
      canvas.drawLine(
        Offset(sunX + cos(angle) * innerR, sunY + sin(angle) * innerR),
        Offset(sunX + cos(angle) * outerR, sunY + sin(angle) * outerR),
        rayPaint,
      );
    }

    // Subtle stars
    final starPaint = Paint()..color = Color.fromRGBO(255, 255, 255, 0.04 + sin(progress * 2 * pi) * 0.02);
    final rng = Random(42);
    for (int i = 0; i < 6; i++) {
      final sx = rng.nextDouble() * size.width * 0.6;
      final sy = rng.nextDouble() * size.height * 0.5;
      final sr = 1.0 + sin(progress * 2 * pi + i * 1.3) * 0.5;
      canvas.drawCircle(Offset(sx, sy), sr, starPaint);
    }
  }

  void _paintClouds(Canvas canvas, Size size) {
    // Cloud count and opacity scale with actual cloud cover %
    // 0% = no clouds, 100% = thick cover
    final numClouds = (_cloudFraction * 6).round().clamp(1, 6);
    final baseOpacity = 0.03 + _cloudFraction * 0.12; // 0.03 at 0% → 0.15 at 100%

    final cloudPaint = Paint()..color = Color.fromRGBO(255, 255, 255, baseOpacity);

    for (int i = 0; i < numClouds; i++) {
      // Extremely slow horizontal drift — takes full 60s cycle
      final driftOffset = slowProgress * size.width * 0.4;
      final baseX = (i * size.width * 0.28 + driftOffset) % (size.width + 80) - 40;
      final baseY = size.height * (0.08 + i * 0.14);

      // Cloud size scales with coverage
      final sizeScale = 0.6 + _cloudFraction * 0.4;
      final w = (35.0 + i * 12) * sizeScale;
      final h = (10.0 + i * 3) * sizeScale;

      // Main cloud body
      canvas.drawOval(
        Rect.fromCenter(center: Offset(baseX, baseY), width: w, height: h),
        cloudPaint,
      );
      // Cloud bumps
      canvas.drawOval(
        Rect.fromCenter(center: Offset(baseX + w * 0.25, baseY - h * 0.35), width: w * 0.6, height: h * 0.75),
        cloudPaint,
      );
      canvas.drawOval(
        Rect.fromCenter(center: Offset(baseX - w * 0.15, baseY - h * 0.25), width: w * 0.45, height: h * 0.65),
        cloudPaint,
      );
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final rainPaint = Paint()
      ..color = const Color.fromRGBO(56, 189, 248, 0.15)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final rng = Random(17);
    for (int i = 0; i < 20; i++) {
      final x = rng.nextDouble() * size.width;
      final startY = (rng.nextDouble() * size.height * 1.2 + progress * size.height * 1.5) % (size.height + 20) - 10;
      final length = 6.0 + rng.nextDouble() * 8;
      canvas.drawLine(
        Offset(x, startY),
        Offset(x - 1, startY + length),
        rainPaint,
      );
    }
  }

  void _paintSnow(Canvas canvas, Size size) {
    final snowPaint = Paint()..color = const Color.fromRGBO(255, 255, 255, 0.12);

    final rng = Random(31);
    for (int i = 0; i < 15; i++) {
      final x = (rng.nextDouble() * size.width + sin(progress * 2 * pi + i) * 8) % size.width;
      final y = (rng.nextDouble() * size.height * 1.3 + progress * size.height * 0.8) % (size.height + 10) - 5;
      final r = 1.2 + rng.nextDouble() * 1.5;
      canvas.drawCircle(Offset(x, y), r, snowPaint);
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    final fogPaint = Paint();
    for (int i = 0; i < 5; i++) {
      final y = size.height * (0.2 + i * 0.15) + sin(slowProgress * 2 * pi + i * 0.8) * 8;
      final opacity = 0.04 + sin(slowProgress * 2 * pi + i) * 0.015;
      fogPaint.color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.01, 0.08));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(size.width * 0.5 + sin(slowProgress * 2 * pi + i * 1.5) * 20, y),
          width: size.width * 0.9,
          height: 14,
        ),
        fogPaint,
      );
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final flashPhase = (progress * 3) % 1.0;
    if (flashPhase < 0.05) {
      final flashPaint = Paint()
        ..color = const Color.fromRGBO(251, 191, 36, 0.08);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), flashPaint);
    }

    if (flashPhase > 0.02 && flashPhase < 0.06) {
      final boltPaint = Paint()
        ..color = const Color.fromRGBO(251, 191, 36, 0.2)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      final bx = size.width * 0.65;
      final by = size.height * 0.1;
      path.moveTo(bx, by);
      path.lineTo(bx - 4, by + 12);
      path.lineTo(bx + 2, by + 12);
      path.lineTo(bx - 2, by + 24);
      canvas.drawPath(path, boltPaint);
    }
  }

  @override
  bool shouldRepaint(_WeatherPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      slowProgress != oldDelegate.slowProgress ||
      type != oldDelegate.type ||
      cloudCover != oldDelegate.cloudCover;
}
