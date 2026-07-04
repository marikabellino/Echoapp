class EventModel {
  final String id;
  final String title;
  final String venueName;
  final String city;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? coverImageUrl;
  final String description;
  final DateTime createdAt;

  const EventModel({
    required this.id,
    required this.title,
    required this.venueName,
    required this.city,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.startsAt,
    required this.endsAt,
    this.coverImageUrl,
    this.description = '',
    required this.createdAt,
  });

  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get hasEnded => DateTime.now().isAfter(endsAt);

  factory EventModel.fromJson(Map<String, dynamic> json) => EventModel(
    id: json['id'] as String,
    title: json['title'] as String,
    venueName: json['venue_name'] as String,
    city: json['city'] as String,
    latitude: (json['latitude'] as num).toDouble(),
    longitude: (json['longitude'] as num).toDouble(),
    radiusMeters: (json['radius_meters'] as num).toDouble(),
    startsAt: DateTime.parse(json['starts_at'] as String),
    endsAt: DateTime.parse(json['ends_at'] as String),
    coverImageUrl: json['cover_image_url'] as String?,
    description: json['description'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String),
  );
}
