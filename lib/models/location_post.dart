class LocationPostImage {
  final String id;
  final String url;
  final String contentType;

  LocationPostImage({
    required this.id,
    required this.url,
    required this.contentType,
  });

  factory LocationPostImage.fromJson(Map<String, dynamic> json) {
    return LocationPostImage(
      id: json['id'] as String,
      url: json['url'] as String,
      contentType: (json['content_type'] ?? '') as String,
    );
  }
}

class LocationPost {
  final String id;
  final String userId;
  final String locationName;
  final double lat;
  final double lon;
  final String? comment;
  final String visibility; // always "public"
  final DateTime insertedAt;
  final double? distanceKm;
  final List<LocationPostImage> images;

  LocationPost({
    required this.id,
    required this.userId,
    required this.locationName,
    required this.lat,
    required this.lon,
    required this.comment,
    required this.visibility,
    required this.insertedAt,
    required this.distanceKm,
    required this.images,
  });

  factory LocationPost.fromJson(Map<String, dynamic> json) {
    final imagesJson = (json['images'] as List?) ?? const [];
    return LocationPost(
      id: json['id'] as String,
      userId: (json['user_id'] ?? '') as String,
      locationName: (json['location_name'] ?? 'Unknown') as String,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      comment: json['comment'] as String?,
      visibility: (json['visibility'] ?? 'public') as String,
      insertedAt: DateTime.parse(json['inserted_at'] as String).toLocal(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      images: imagesJson.map((e) => LocationPostImage.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}

