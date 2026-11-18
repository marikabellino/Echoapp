import 'package:echo/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:echo/features/profile/domain/models/profile_model.dart';

enum DropVisibility {
  public('public'),
  circle('circle'),
  private('private');

  const DropVisibility(this.value);
  final String value;

  static DropVisibility fromString(String s) => DropVisibility.values
      .firstWhere((v) => v.value == s, orElse: () => DropVisibility.public);

  String get label {
    switch (this) {
      case DropVisibility.public:
        return 'Pubblico';
      case DropVisibility.circle:
        return 'Cerchia';
      case DropVisibility.private:
        return 'Privato';
    }
  }

  IconData get icon {
    switch (this) {
      case DropVisibility.public:
        return Icons.public_outlined;
      case DropVisibility.circle:
        return Icons.people_outline;
      case DropVisibility.private:
        return Icons.lock_outline;
    }
  }
}

enum DropMood {
  drop('drop'),
  love('love'),
  secret('secret'),
  dream('dream'),
  lost('lost'),
  food('food');

  const DropMood(this.value);
  final String value;

  static DropMood fromString(String s) => DropMood.values.firstWhere(
    (m) => m.value == s,
    orElse: () => DropMood.drop,
  );
}

extension DropMoodX on DropMood {
  Color get color {
    switch (this) {
      case DropMood.drop:
        return AppColors.accent;
      case DropMood.love:
        return AppColors.moodLove;
      case DropMood.secret:
        return AppColors.moodSecret;
      case DropMood.dream:
        return AppColors.moodDream;
      case DropMood.lost:
        return AppColors.moodLost;
      case DropMood.food:
        return AppColors.moodFood;
    }
  }

  /// Outline icon representing the mood — used instead of emoji so mood
  /// markers read as part of the app's own icon language, not stickers.
  IconData get icon {
    switch (this) {
      case DropMood.drop:
        return Icons.bolt_rounded;
      case DropMood.love:
        return Icons.favorite_border;
      case DropMood.secret:
        return Icons.diamond_outlined;
      case DropMood.dream:
        return Icons.auto_awesome_outlined;
      case DropMood.lost:
        return Icons.explore_outlined;
      case DropMood.food:
        return Icons.restaurant_outlined;
    }
  }

  String get label {
    switch (this) {
      case DropMood.drop:
        return 'Momento';
      case DropMood.love:
        return 'Amore';
      case DropMood.secret:
        return 'Chicca';
      case DropMood.dream:
        return 'Sogno';
      case DropMood.lost:
        return 'Da scoprire';
      case DropMood.food:
        return 'Cibo';
    }
  }
}

class DropModel {
  final String id;
  final String userId;
  final String description;
  final DropMood mood;
  final double latitude;
  final double longitude;
  final String? locationName;

  static final _coordsPattern = RegExp(r'^\s*-?\d+\.\d+\s*,\s*-?\d+\.\d+\s*$');

  String? get displayLocation {
    final n = locationName?.trim();
    if (n == null || n.isEmpty || _coordsPattern.hasMatch(n)) return null;
    return n;
  }

  final String? imageUrl;
  final int likesCount;
  final bool isLikedByMe;
  final int commentsCount;
  final String? aiCaption;
  final DropVisibility visibility;
  final DateTime createdAt;
  final ProfileModel? author;
  final String? eventId;
  final String? eventTitle;

  // Used by map for discovery radius
  static const double discoveryRadius = 300.0;

  // Short title for map card
  String get title => description.length > 42
      ? '${description.substring(0, 42)}…'
      : description;

  const DropModel({
    required this.id,
    required this.userId,
    required this.description,
    required this.mood,
    required this.latitude,
    required this.longitude,
    this.locationName,
    this.imageUrl,
    this.likesCount = 0,
    this.isLikedByMe = false,
    this.commentsCount = 0,
    this.aiCaption,
    this.visibility = DropVisibility.public,
    required this.createdAt,
    this.author,
    this.eventId,
    this.eventTitle,
  });

  factory DropModel.fromJson(Map<String, dynamic> json) {
    ProfileModel? author;
    final profileRaw = json['profiles'];
    if (profileRaw is Map<String, dynamic>) {
      author = ProfileModel.fromJson(profileRaw);
    }

    String? eventTitle;
    final eventRaw = json['event'];
    if (eventRaw is Map<String, dynamic>) {
      eventTitle = eventRaw['title'] as String?;
    }

    return DropModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      description: json['description'] as String,
      mood: DropMood.fromString(json['mood'] as String? ?? 'echo'),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      locationName: json['location_name'] as String?,
      imageUrl: json['image_url'] as String?,
      likesCount: json['likes_count'] as int? ?? 0,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      commentsCount: json['comments_count'] as int? ?? 0,
      aiCaption: json['ai_caption'] as String?,
      visibility: DropVisibility.fromString(
        json['visibility'] as String? ?? 'public',
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      author: author,
      eventId: json['event_id'] as String?,
      eventTitle: eventTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'description': description,
    'mood': mood.value,
    'latitude': latitude,
    'longitude': longitude,
    'location_name': locationName,
    'image_url': imageUrl,
    'likes_count': likesCount,
    'is_liked_by_me': isLikedByMe,
    'comments_count': commentsCount,
    'ai_caption': aiCaption,
    'visibility': visibility.value,
    'created_at': createdAt.toIso8601String(),
    if (author != null) 'profiles': author!.toCacheJson(),
    'event_id': eventId,
  };

  Map<String, dynamic> toInsertJson() => {
    'user_id': userId,
    'description': description,
    'mood': mood.value,
    'latitude': latitude,
    'longitude': longitude,
    if (locationName != null) 'location_name': locationName,
    if (imageUrl != null) 'image_url': imageUrl,
    if (aiCaption != null) 'ai_caption': aiCaption,
    'visibility': visibility.value,
    if (eventId != null) 'event_id': eventId,
  };

  DropModel copyWith({
    String? id,
    String? userId,
    String? description,
    DropMood? mood,
    double? latitude,
    double? longitude,
    String? locationName,
    String? imageUrl,
    int? likesCount,
    bool? isLikedByMe,
    int? commentsCount,
    String? aiCaption,
    DropVisibility? visibility,
    DateTime? createdAt,
    ProfileModel? author,
    String? eventId,
    String? eventTitle,
    // Toglie la foto (es. link firmato negato): `imageUrl: null` non basta,
    // perché null qui significa "lascia quella che c'è".
    bool clearImage = false,
  }) {
    return DropModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      description: description ?? this.description,
      mood: mood ?? this.mood,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      aiCaption: aiCaption ?? this.aiCaption,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      author: author ?? this.author,
      eventId: eventId ?? this.eventId,
      eventTitle: eventTitle ?? this.eventTitle,
    );
  }
}
