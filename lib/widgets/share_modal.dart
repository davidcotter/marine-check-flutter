import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/marine_data.dart';
import '../services/location_service.dart';
import '../utils/unit_converter.dart';
import '../utils/share_image_builder.dart';
import 'forecast_summary_card.dart';
import '../utils/web_share_stub.dart'
    if (dart.library.html) '../utils/web_share_web.dart' as web_share;

class ShareModal extends StatefulWidget {
  final SavedLocation location;
  final HourlyForecast forecast;

  const ShareModal({
    super.key,
    required this.location,
    required this.forecast,
  });

  @override
  State<ShareModal> createState() => _ShareModalState();
}

class _ShareModalState extends State<ShareModal> {
  final TextEditingController _messageController = TextEditingController();
  bool _sharing = false;

  String _buildShareText() {
    final f = widget.forecast;
    final comment = _messageController.text.trim();
    final time = DateFormat('EEE d MMM @ HH:mm').format(f.time);
    final roughness = UnitConverter.getRoughnessStatus(f.swimCondition.roughnessIndex);
    final wind = UnitConverter.formatWind(f.weather.windSpeed.toDouble());
    final wave = UnitConverter.formatHeight(f.swell.height);
    final lines = [
      '🌊 ${widget.location.name} — $time',
      roughness.label,
      '💨 $wind  🌊 $wave',
      if (comment.isNotEmpty) comment,
      'https://dipreport.com',
    ];
    return lines.join('\n');
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final comment = _messageController.text.trim();
      final text = _buildShareText();

      // Build the share image
      final pngBytes = await buildShareImage(
        location: widget.location,
        forecast: widget.forecast,
        comment: comment.isNotEmpty ? comment : null,
      );

      if (kIsWeb) {
        // Try image share first, fall back to text, then clipboard
        final sharedImage = await web_share.shareImage(
          pngBytes, 'dipreport.png', text,
        );
        if (!sharedImage) {
          final sharedText = await web_share.shareText(text);
          if (!sharedText) {
            await Clipboard.setData(ClipboardData(text: text));
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            }
          }
        }
      } else {
        // Native: share image file
        await Share.shareXFiles(
          [XFile.fromData(pngBytes, mimeType: 'image/png', name: 'dipreport.png')],
          text: text,
        );
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Share Dip Report',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ForecastSummaryCard(
              title: '${widget.location.name} · ${DateFormat('EEE d MMM @ HH:mm').format(widget.forecast.time)}',
              forecasts: [widget.forecast],
              message: _messageController.text,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _messageController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Add a comment (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: cs.surface,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            // Disclaimer
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'ℹ️  Always swim within your ability and stay within your depth. '
                'Conditions can change — use your own judgement.',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 11, height: 1.4),
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.ios_share),
                label: const Text(
                  'Share Dip Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
