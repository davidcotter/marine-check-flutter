import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/marine_data.dart';
import '../services/location_service.dart';
import '../utils/unit_converter.dart';
import 'package:intl/intl.dart';

/// Renders a 1200×630 share card mirroring the "Next 2 hours" panel layout.
Future<Uint8List> buildShareImage({
  required SavedLocation location,
  required HourlyForecast forecast,
  String? comment,
}) async {
  const w = 1200.0;
  const h = 630.0;
  const pad = 64.0;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

  final roughness = UnitConverter.getRoughnessStatus(forecast.swimCondition.roughnessIndex);
  final roughColor = Color(roughness.color);
  final wind = UnitConverter.formatWind(forecast.weather.windSpeed.toDouble());
  final wave = '${forecast.swell.height.toStringAsFixed(1)}m';
  final temp = UnitConverter.formatTemp(forecast.weather.temperature);
  final waterTemp = '${forecast.swell.seaTemperature.round()}°C';
  final rain = '${forecast.weather.precipitationProbability}%';
  final timeStr = DateFormat('EEE d MMM · HH:mm').format(forecast.time);

  // ── Background ───────────────────────────────────────────────────────────
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        [const Color(0xFF0D1B2E), const Color(0xFF0F2744)],
      ),
  );

  // Subtle radial glow
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.radial(
        Offset(w * 0.7, h * 0.15),
        w * 0.5,
        [const Color(0xFF1E3A5F).withOpacity(0.45), Colors.transparent],
      ),
  );

  // ── Left accent bar ───────────────────────────────────────────────────────
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      const Rect.fromLTWH(0, 0, 10, h),
      topRight: const Radius.circular(4),
      bottomRight: const Radius.circular(4),
    ),
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(0, 0),
        Offset(0, h),
        [roughColor, roughColor.withOpacity(0.3)],
      ),
  );

  // ── Text helpers ─────────────────────────────────────────────────────────
  TextPainter _tp(String text, {
    double fontSize = 32,
    Color color = Colors.white,
    FontWeight weight = FontWeight.normal,
    double? maxWidth,
    TextAlign align = TextAlign.left,
    double letterSpacing = 0,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color, fontWeight: weight,
            height: 1.2, letterSpacing: letterSpacing),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: maxWidth ?? w);
  }

  void drawText(String text, Offset offset, {
    double fontSize = 32, Color color = Colors.white,
    FontWeight weight = FontWeight.normal, double? maxWidth,
    TextAlign align = TextAlign.left, double letterSpacing = 0,
  }) {
    _tp(text, fontSize: fontSize, color: color, weight: weight,
        maxWidth: maxWidth, align: align, letterSpacing: letterSpacing)
        .paint(canvas, offset);
  }

  // ── Location ──────────────────────────────────────────────────────────────
  drawText(location.name, const Offset(pad, 52),
      fontSize: 68, weight: FontWeight.w800, maxWidth: w - pad * 2, letterSpacing: -1);

  // ── Date/time ─────────────────────────────────────────────────────────────
  drawText(timeStr, const Offset(pad, 134),
      fontSize: 30, color: const Color(0xFF7FA8C9));

  // ── Sea state badge ───────────────────────────────────────────────────────
  const badgeTop = 188.0;
  const badgeH = 50.0;
  const badgePad = 26.0;
  final labelTp = _tp(roughness.label.toUpperCase(),
      fontSize: 24, weight: FontWeight.w700, letterSpacing: 1.5);
  final badgeW = labelTp.width + badgePad * 2;
  final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, badgeTop, badgeW, badgeH), const Radius.circular(25));
  canvas.drawRRect(badgeRect, Paint()..color = roughColor.withOpacity(0.18));
  canvas.drawRRect(badgeRect, Paint()
    ..color = roughColor.withOpacity(0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.5);
  labelTp.paint(canvas, Offset(pad + badgePad, badgeTop + (badgeH - labelTp.height) / 2));

  // ── Divider ───────────────────────────────────────────────────────────────
  canvas.drawLine(Offset(pad, 268), Offset(w - pad, 268),
      Paint()..color = const Color(0xFF1E3A5F)..strokeWidth = 1.5);

  // ── 3-column panel (mirrors "Next 2 hours") ───────────────────────────────
  // Col 1: Weather  |  Col 2: Tide/Waves  |  Col 3: Sea State
  const colTop = 300.0;
  const colW = (w - pad * 2) / 3;

  // Weather icon (WMO)
  String wmoIcon() {
    final c = forecast.weather.wmoCode;
    if (c == 0) return '☀️';
    if (c <= 3) return '⛅';
    if (c <= 48) return '🌫️';
    if (c <= 67) return '🌧️';
    if (c <= 77) return '🌨️';
    if (c <= 82) return '🌧️';
    if (c <= 86) return '🌨️';
    return '⛈️';
  }

  // Col 1 — Weather
  drawText(wmoIcon(), Offset(pad, colTop), fontSize: 56);
  drawText(temp, Offset(pad, colTop + 72), fontSize: 52, weight: FontWeight.w700);
  drawText(wind, Offset(pad, colTop + 136), fontSize: 28, color: const Color(0xFF94A3B8));
  drawText('💧$rain', Offset(pad, colTop + 172), fontSize: 26, color: const Color(0xFF38BDF8));

  // Col 2 — Tide graphic (drawn, same as TideGraphic widget) + wave height
  final c2x = pad + colW;
  final tideData = forecast.tide;
  if (tideData != null) {
    final tideColor = Color(UnitConverter.getTideColor(tideData.status));
    final tgW = 120.0;
    final tgH = 64.0;
    final tgLeft = c2x;
    final tgTop = colTop.toDouble();
    final tgRect = Rect.fromLTWH(tgLeft, tgTop, tgW, tgH);
    final tgRRect = RRect.fromRectAndRadius(tgRect, const Radius.circular(6));

    // Background
    canvas.drawRRect(tgRRect, Paint()..color = tideColor.withOpacity(0.1));
    // Border
    canvas.drawRRect(tgRRect, Paint()
      ..color = tideColor.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);

    // Filled wave — clip to rect
    canvas.save();
    canvas.clipRRect(tgRRect);
    final pct = (tideData.percentage / 100.0).clamp(0.0, 1.0);
    final yBase = tgTop + tgH * (1.0 - pct);
    final tidePath = Path()
      ..moveTo(tgLeft, tgTop + tgH)
      ..lineTo(tgLeft, yBase);
    for (double x = 0; x <= tgW; x++) {
      final y = yBase + 3 * math.sin((x / tgW) * 2 * math.pi);
      tidePath.lineTo(tgLeft + x, y);
    }
    tidePath
      ..lineTo(tgLeft + tgW, tgTop + tgH)
      ..close();
    canvas.drawPath(tidePath, Paint()..color = tideColor.withOpacity(0.6));
    canvas.restore();

    // Tide height + arrow
    final tideArrow = tideData.isRising ? '↑' : '↓';
    drawText(
      '${UnitConverter.formatHeight(tideData.level)} $tideArrow',
      Offset(c2x, colTop + tgH + 10),
      fontSize: 30, weight: FontWeight.w700, color: tideColor,
    );
    drawText('tide', Offset(c2x, colTop + tgH + 52),
        fontSize: 24, color: const Color(0xFF64748B));
  } else {
    drawText('--', Offset(c2x, colTop + 20), fontSize: 36, color: const Color(0xFF64748B));
    drawText('tide', Offset(c2x, colTop + 68), fontSize: 24, color: const Color(0xFF64748B));
  }

  // Col 3 — Sea state: drawn sine waves, amplitude + count by roughness
  final c3x = pad + colW * 2;
  final waveCount = forecast.swimCondition.roughnessIndex <= 20 ? 1

      : forecast.swimCondition.roughnessIndex <= 40 ? 2 : 3;
  final amplitude = forecast.swimCondition.roughnessIndex <= 20 ? 12.0
      : forecast.swimCondition.roughnessIndex <= 40 ? 20.0
      : forecast.swimCondition.roughnessIndex <= 60 ? 30.0 : 42.0;

  final waveAreaW = 180.0;
  final waveAreaH = 80.0;
  final waveStartY = colTop + waveAreaH / 2;

  for (int wi = 0; wi < waveCount; wi++) {
    final yOffset = (wi - (waveCount - 1) / 2.0) * (amplitude * 1.6);
    final wavePath = Path();
    final period = waveAreaW / 2;
    wavePath.moveTo(c3x, waveStartY + yOffset);
    for (double x = 0; x <= waveAreaW; x += period / 2) {
      final cp1x = c3x + x + period / 4;
      final cp1y = waveStartY + yOffset - amplitude;
      final cp2x = c3x + x + period * 3 / 4;
      final cp2y = waveStartY + yOffset + amplitude;
      final endX = c3x + x + period;
      wavePath.cubicTo(cp1x, cp1y, cp2x, cp2y, endX, waveStartY + yOffset);
    }
    canvas.drawPath(
      wavePath,
      Paint()
        ..color = roughColor.withOpacity(0.9 - wi * 0.15)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 - wi * 0.5
        ..strokeCap = StrokeCap.round,
    );
  }

  drawText(roughness.label, Offset(c3x, colTop + waveAreaH + 12), fontSize: 36,
      weight: FontWeight.w700, color: roughColor);
  drawText('sea state', Offset(c3x, colTop + waveAreaH + 58), fontSize: 24,
      color: const Color(0xFF64748B));

  // ── Comment ───────────────────────────────────────────────────────────────
  if (comment != null && comment.isNotEmpty) {
    canvas.drawLine(Offset(pad, 510), Offset(w - pad, 510),
        Paint()..color = const Color(0xFF1E3A5F)..strokeWidth = 1);
    drawText('"$comment"', const Offset(pad, 524),
        fontSize: 26, color: const Color(0xFF94A3B8), maxWidth: w - pad * 2 - 200);
  }

  // ── Branding ──────────────────────────────────────────────────────────────
  drawText('🌊', Offset(w - pad - 52, h - 88), fontSize: 48);
  final brandTp = _tp('dipreport.com', fontSize: 26,
      color: const Color(0xFF3B82F6), weight: FontWeight.w700);
  brandTp.paint(canvas, Offset(w - pad - brandTp.width, h - 42));

  // ── Render ────────────────────────────────────────────────────────────────
  final picture = recorder.endRecording();
  final image = await picture.toImage(w.toInt(), h.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
