import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/location_service.dart';
import '../services/location_post_service.dart';
import '../services/auth_service.dart';
import '../models/location_post.dart';
import '../widgets/location_post_card.dart';
import '../utils/web_image_picker_stub.dart'
    if (dart.library.html) '../utils/web_image_picker_web.dart' as web_picker;
import 'login_screen.dart';

class LocationPostsScreen extends StatefulWidget {
  final SavedLocation location;
  final DateTime? forecastTimeUtc;
  final String? initialPostId;
  final bool initialCompose;

  const LocationPostsScreen({
    super.key,
    required this.location,
    this.forecastTimeUtc,
    this.initialPostId,
    this.initialCompose = false,
  });

  @override
  State<LocationPostsScreen> createState() => _LocationPostsScreenState();
}

class _LocationPostsScreenState extends State<LocationPostsScreen>
    with SingleTickerProviderStateMixin {
  final _service = LocationPostService();

  bool _loadingAll = true;
  bool _loadingMine = false;
  List<LocationPost> _allPosts = [];
  List<LocationPost> _myPosts = [];
  String? _error;
  bool _autoComposeDone = false;

  @override
  void initState() {
    super.initState();
    _loadAllPosts();
    _loadMyPosts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeAutoCompose();
    });
  }

  Future<void> _loadAllPosts() async {
    setState(() {
      _error = null;
      _loadingAll = true;
    });

    try {
      // Returns posts sorted by distance (nearest first)
      var posts = await _service.listNearbyPublic(
        lat: widget.location.lat,
        lon: widget.location.lon,
        radiusKm: 50.0,
      );
      if (!mounted) return;

      // Ensure the shared/initial post is visible
      if (widget.initialPostId != null && widget.initialPostId!.isNotEmpty) {
        final already = posts.any((p) => p.id == widget.initialPostId);
        if (!already) {
          try {
            final p = await _service.fetchPost(widget.initialPostId!);
            posts = [p, ...posts];
          } catch (_) {}
        }
      }

      setState(() {
        _allPosts = posts;
        _loadingAll = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingAll = false;
        _error = 'Failed to load posts';
      });
    }
  }

  Future<void> _loadMyPosts() async {
    if (!AuthService().isAuthenticated) return;
    setState(() => _loadingMine = true);
    try {
      final posts = await _service.listMyPosts();
      if (!mounted) return;
      setState(() {
        _myPosts = posts;
        _loadingMine = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMine = false);
    }
  }

  Future<void> _reload() async {
    await Future.wait([_loadAllPosts(), _loadMyPosts()]);
  }

  Future<void> _createPost() async {
    if (!AuthService().isAuthenticated) {
      String? returnTo;
      if (kIsWeb) {
        final ts =
            ((widget.forecastTimeUtc ?? DateTime.now().toUtc()).millisecondsSinceEpoch / 1000)
                .round();
        final v =
            '${widget.location.lat.toStringAsFixed(4)},${widget.location.lon.toStringAsFixed(4)},${Uri.encodeComponent(widget.location.name)},$ts';
        returnTo = '/?view=posts&compose=1&v=$v';
      }
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoginScreen(returnToOverride: returnTo)),
      );
      if (!mounted) return;
      if (!AuthService().isAuthenticated) return;
    }

    final created = await showModalBottomSheet<LocationPost>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CreatePostSheet(location: widget.location, forecastTimeUtc: widget.forecastTimeUtc),
    );

    if (created != null) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Posted!')));
    }
  }

  Future<void> _maybeAutoCompose() async {
    if (_autoComposeDone || !widget.initialCompose) return;
    _autoComposeDone = true;
    if (!mounted) return;
    await _createPost();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = AuthService().isAuthenticated;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Swimmer posts'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _reload,
              tooltip: 'Refresh',
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Nearby ${widget.location.name}'),
              const Tab(text: 'My posts'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _createPost,
          icon: const Icon(Icons.add_a_photo),
          label: const Text('Post photo'),
        ),
        body: Column(
          children: [
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ),
            Expanded(
              child: TabBarView(
                children: [
                  _PostsList(
                    loading: _loadingAll,
                    posts: _allPosts,
                    emptyText: 'No posts nearby yet.',
                    onDeleted: _reload,
                  ),
                  isLoggedIn
                      ? _PostsList(
                          loading: _loadingMine,
                          posts: _myPosts,
                          emptyText: "You haven't posted anything yet.",
                          onDeleted: _reload,
                        )
                      : _LoginPrompt(onLogin: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          );
                          if (!mounted) return;
                          await _loadMyPosts();
                          setState(() {});
                        }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoginPrompt extends StatelessWidget {
  final VoidCallback onLogin;
  const _LoginPrompt({required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Sign in to see your posts',
              style: TextStyle(fontSize: 16, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onLogin, child: const Text('Sign in')),
          ],
        ),
      ),
    );
  }
}

class _PostsList extends StatelessWidget {
  final bool loading;
  final List<LocationPost> posts;
  final String emptyText;
  final VoidCallback? onDeleted;

  const _PostsList({
    required this.loading,
    required this.posts,
    required this.emptyText,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (context, i) => LocationPostCard(post: posts[i], onDeleted: onDeleted),
    );
  }
}

class _CreatePostSheet extends StatefulWidget {
  final SavedLocation location;
  final DateTime? forecastTimeUtc;

  const _CreatePostSheet({
    required this.location,
    required this.forecastTimeUtc,
  });

  @override
  State<_CreatePostSheet> createState() => _CreatePostSheetState();
}

class _CreatePostSheetState extends State<_CreatePostSheet> {
  final _picker = ImagePicker();
  final _commentController = TextEditingController();
  bool _submitting = false;

  Uint8List? _imageBytes;
  String? _filename;
  List<SavedLocation> _locations = [];
  SavedLocation? _selectedLocation;
  bool _loadingLocations = true;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locs = await LocationService().getSavedLocations();
      if (!mounted) return;
      final match = locs.where((l) => l.id == widget.location.id);
      setState(() {
        if (match.isNotEmpty) {
          _locations = locs;
          _selectedLocation = match.first;
        } else {
          _locations = [widget.location, ...locs];
          _selectedLocation = widget.location;
        }
        _loadingLocations = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locations = [widget.location];
        _selectedLocation = widget.location;
        _loadingLocations = false;
      });
    }
  }

  Future<void> _pick(ImageSource source) async {
    try {
      if (kIsWeb) {
        final picked =
            await web_picker.pickWebImage(preferCamera: source == ImageSource.camera);
        if (picked == null) {
          if (!mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('No image selected')));
          return;
        }
        if (!mounted) return;
        setState(() {
          _imageBytes = picked.bytes;
          _filename = picked.name.isNotEmpty ? picked.name : 'upload.jpg';
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Selected: $_filename (${(_imageBytes!.length / 1024).round()} KB)')),
        );
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Image picker failed: $e')));
    }
  }

  Future<void> _submit() async {
    if (_imageBytes == null || _filename == null) return;
    if (_selectedLocation == null) return;

    setState(() => _submitting = true);
    try {
      final post = await LocationPostService().createPost(
        lat: _selectedLocation!.lat,
        lon: _selectedLocation!.lon,
        locationName: _selectedLocation!.name,
        imageBytes: _imageBytes!,
        filename: _filename!,
        comment:
            _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
        forecastTimeUtc: widget.forecastTimeUtc,
      );

      if (!mounted) return;

      await LocationPostService().generatePreview(postId: post.id);

      final url = LocationPostService().buildShareUrl(post.id);
      await Share.share(url);

      if (!mounted) return;
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Post failed: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Post a photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 10),
          if (_imageBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.memory(_imageBytes!, fit: BoxFit.cover),
              ),
            )
          else
            Container(
              height: 180,
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: Theme.of(context).dividerColor.withOpacity(0.2)),
              ),
              child: Center(
                child: Text('Add a photo', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _submitting ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ),
            ],
          ),
          if (_filename != null && _imageBytes != null) ...[
            const SizedBox(height: 8),
            Text(
              'Selected: $_filename • ${(_imageBytes!.length / 1024).round()} KB',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          if (_loadingLocations)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child:
                  LinearProgressIndicator(minHeight: 2, backgroundColor: Colors.transparent),
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedLocation?.id,
              decoration: InputDecoration(
                labelText: 'Location',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: cs.surface,
              ),
              items: _locations
                  .map(
                    (l) => DropdownMenuItem(
                      value: l.id,
                      child: Text(l.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: _submitting
                  ? null
                  : (id) {
                      final match = _locations.where((l) => l.id == id);
                      if (match.isEmpty) return;
                      setState(() => _selectedLocation = match.first);
                    },
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Add a comment (optional)',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: cs.surface,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.public, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('This post will be public',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: (_imageBytes == null || _submitting) ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Upload & Share',
                      style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
