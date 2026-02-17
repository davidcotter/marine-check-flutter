import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

import '../models/location_post.dart';
import 'auth_service.dart';

class LocationPostService {
  static final LocationPostService _instance = LocationPostService._internal();
  factory LocationPostService() => _instance;
  LocationPostService._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  late final Dio _dio;

  String get _baseUrl {
    if (kIsWeb) return '/api';
    if (kDebugMode) return 'http://10.0.2.2:4040/api';
    return 'https://dipreport.com/api';
  }

  Future<LocationPost> fetchPost(String id) async {
    final res = await _dio.get('/location-posts/$id');
    return LocationPost.fromJson(res.data['post'] as Map<String, dynamic>);
  }

  Future<List<LocationPost>> listPublicByLocation({
    required double lat,
    required double lon,
    double radiusKm = 2.0,
    int limit = 30,
  }) async {
    final res = await _dio.get('/public/location-posts/by-location', queryParameters: {
      'lat': lat,
      'lon': lon,
      'radius_km': radiusKm,
      'limit': limit,
    });

    final list = (res.data['posts'] as List?) ?? const [];
    return list.map((e) => LocationPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LocationPost>> listNearbyPublic({
    required double lat,
    required double lon,
    double radiusKm = 50.0,
    int limit = 30,
  }) async {
    final res = await _dio.get('/public/location-posts/nearby', queryParameters: {
      'lat': lat,
      'lon': lon,
      'radius_km': radiusKm,
      'limit': limit,
    });

    final list = (res.data['posts'] as List?) ?? const [];
    return list.map((e) => LocationPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<LocationPost>> listMyPosts({int limit = 50}) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) return [];

    final res = await _dio.get('/location-posts/mine',
      queryParameters: {'limit': limit},
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    final list = (res.data['posts'] as List?) ?? const [];
    return list.map((e) => LocationPost.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<LocationPost> createPost({
    required double lat,
    required double lon,
    required String locationName,
    required List<int> imageBytes,
    required String filename,
    String? comment,
    DateTime? forecastTimeUtc,
  }) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated');
    }

    final form = FormData.fromMap({
      'lat': lat.toString(),
      'lon': lon.toString(),
      'location_name': locationName,
      'comment': comment,
      if (forecastTimeUtc != null) 'forecast_time': forecastTimeUtc.toIso8601String(),
      'image': MultipartFile.fromBytes(imageBytes, filename: filename),
    });

    final res = await _dio.post(
      '/location-posts',
      data: form,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );

    return LocationPost.fromJson(res.data['post'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String id) async {
    final token = AuthService().token;
    if (token == null || token.isEmpty) {
      throw Exception('Not authenticated');
    }

    await _dio.delete(
      '/location-posts/$id',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  /// Pre-generate the share preview PNG on the server so WhatsApp gets a static file.
  Future<String?> generatePreview({String? postId, double? lat, double? lon, String? loc, int? ts, String? comment}) async {
    try {
      final Map<String, dynamic> body = {};
      if (postId != null) {
        body['post_id'] = postId;
      } else {
        body['lat'] = lat.toString();
        body['lon'] = lon.toString();
        body['loc'] = loc;
        if (ts != null) body['ts'] = ts.toString();
        if (comment != null && comment.isNotEmpty) body['comment'] = comment;
      }
      final res = await _dio.post('/share/preview', data: body);
      return res.data['preview_url'] as String?;
    } catch (_) {
      return null;
    }
  }

  String buildShareUrl(String postId) {
    // Use first 8 chars of UUID for a short, clean URL
    final shortId = postId.length >= 8 ? postId.substring(0, 8) : postId;
    if (kIsWeb) return '${Uri.base.origin}/s/$shortId';
    return 'https://dipreport.com/s/$shortId';
  }
}

