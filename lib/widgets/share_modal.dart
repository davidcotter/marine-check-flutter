import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import '../models/marine_data.dart';
import '../services/location_service.dart';
import '../services/location_post_service.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';
import '../utils/web_image_picker_stub.dart'
    if (dart.library.html) '../utils/web_image_picker_web.dart' as web_picker;
import 'forecast_summary_card.dart';

class ShareModal extends StatefulWidget {
  final SavedLocation location;
  final HourlyForecast forecast;
  final String baseUrl;

  const ShareModal({
    super.key,
    required this.location,
    required this.forecast,
    required this.baseUrl,
  });

  @override
  State<ShareModal> createState() => _ShareModalState();
}

class _ShareModalState extends State<ShareModal> {
  final TextEditingController _messageController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _imageBytes;
  String? _filename;
  bool _submitting = false;

  Future<void> _pickImage(ImageSource source) async {
    try {
      if (kIsWeb) {
        final picked = await web_picker.pickWebImage(preferCamera: source == ImageSource.camera);
        if (picked == null) return;
        if (!mounted) return;
        setState(() {
          _imageBytes = picked.bytes;
          _filename = picked.name.isNotEmpty ? picked.name : 'upload.jpg';
        });
        return;
      }

      final x = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1400,
        maxHeight: 1400,
      );
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _filename = x.name.isNotEmpty ? x.name : 'upload.jpg';
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image picker failed: $e')),
      );
    }
  }

  void _removeImage() {
    setState(() {
      _imageBytes = null;
      _filename = null;
    });
  }

  Future<void> _share() async {
    final comment = _messageController.text.trim();
    final hasPhoto = _imageBytes != null && _filename != null;

    if (hasPhoto) {
      // Need to be authenticated to create a post
      if (!AuthService().isAuthenticated) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        if (!mounted) return;
        if (!AuthService().isAuthenticated) return;
      }

      setState(() => _submitting = true);
      try {
        final post = await LocationPostService().createPost(
          lat: widget.location.lat,
          lon: widget.location.lon,
          locationName: widget.location.name,
          imageBytes: _imageBytes!,
          filename: _filename!,
          comment: comment.isNotEmpty ? comment : null,
          forecastTimeUtc: widget.forecast.time.toUtc(),
        );

        // Pre-generate the preview image on the server before sharing
        await LocationPostService().generatePreview(postId: post.id);

        final url = LocationPostService().buildShareUrl(post.id);

        if (kIsWeb) {
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link copied to clipboard!')),
            );
          }
        } else {
          await Share.share(url);
        }

        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
    } else {
      // No photo — share a forecast link
      setState(() => _submitting = true);
      try {
        final f = widget.forecast;
        final ts = (f.time.toUtc().millisecondsSinceEpoch / 1000).round();
        final lat = widget.location.lat;
        final lon = widget.location.lon;
        final loc = Uri.encodeComponent(widget.location.name);
        final commentParam = comment.isNotEmpty ? '&comment=${Uri.encodeComponent(comment)}' : '';
        final cb = DateTime.now().millisecondsSinceEpoch;
        final shareUrl = 'https://dipreport.com/share/forecast?lat=$lat&lon=$lon&loc=$loc&ts=$ts$commentParam';

        // Pre-generate the preview image on the server before sharing
        await LocationPostService().generatePreview(
          lat: widget.location.lat,
          lon: widget.location.lon,
          loc: widget.location.name,
          ts: ts,
          comment: comment.isNotEmpty ? comment : null,
        );

        if (kIsWeb) {
          await Clipboard.setData(ClipboardData(text: shareUrl));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Link copied to clipboard!')),
            );
          }
        } else {
          await Share.share(shareUrl);
        }

        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Share failed: $e')),
        );
      } finally {
        if (mounted) setState(() => _submitting = false);
      }
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
            // Title
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

            // Weather preview
            ForecastSummaryCard(
              title:
                  '${widget.location.name} · ${DateFormat('EEE d MMM @ HH:mm').format(widget.forecast.time)}',
              forecasts: [widget.forecast],
              message: _messageController.text,
            ),
            const SizedBox(height: 14),

            // Photo section
            if (_imageBytes != null) ...[
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.close, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ] else ...[
              // Photo picker buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _pickImage(ImageSource.camera),
                      icon: const Icon(Icons.photo_camera, size: 18),
                      label: const Text('Camera'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : () => _pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text('Gallery'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Optional — add a photo to your dip report',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Message input
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

            // Share button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _submitting ? null : _share,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(kIsWeb ? Icons.link : Icons.ios_share),
                label: Text(
                  kIsWeb ? 'Copy Link' : 'Share Dip Report',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
