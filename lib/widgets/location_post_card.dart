import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/location_post.dart';
import '../services/auth_service.dart';
import '../services/location_post_service.dart';

class LocationPostCard extends StatelessWidget {
  final LocationPost post;
  final bool showLocationName;
  final VoidCallback? onDeleted;

  const LocationPostCard({
    super.key,
    required this.post,
    this.showLocationName = true,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final image = post.images.isNotEmpty ? post.images.first : null;
    final currentUserId = AuthService().user?['id']?.toString();
    final isOwner = currentUserId != null && currentUserId.isNotEmpty && currentUserId == post.userId;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withOpacity(0.15)),
        boxShadow: theme.brightness == Brightness.light
            ? [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 6))]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (image != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  image.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: cs.surfaceContainerHighest,
                    child: Center(
                      child: Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 160,
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Center(child: Icon(Icons.photo_outlined, color: cs.onSurfaceVariant, size: 44)),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (showLocationName)
                      Expanded(
                        child: Text(
                          post.locationName,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (post.distanceKm != null) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${post.distanceKm!.toStringAsFixed(post.distanceKm! < 10 ? 1 : 0)} km',
                          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                      ),
                    ],
                    if (isOwner) ...[
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        iconSize: 20,
                        tooltip: 'Delete',
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Delete post?'),
                              content: const Text('This will permanently delete the photo and comment.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          );
                          if (ok != true) return;
                          try {
                            await LocationPostService().deletePost(post.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
                            }
                            onDeleted?.call();
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
                            }
                          }
                        },
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('EEE d MMM • HH:mm').format(post.insertedAt),
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                if (post.comment != null && post.comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    post.comment!,
                    style: TextStyle(color: cs.onSurface, fontSize: 14, height: 1.3),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.public, size: 16, color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text('Public', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        // Pre-generate the preview image before sharing
                        await LocationPostService().generatePreview(postId: post.id);
                        final url = LocationPostService().buildShareUrl(post.id);
                        await Share.share(url);
                      },
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text('Share Dip Report'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

