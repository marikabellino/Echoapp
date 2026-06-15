import 'package:flutter/material.dart';
import 'package:apptest/features/profile/domain/models/profile_model.dart';

enum MemoryVisibility {
  public('public'),
  circle('circle'),
  private('private');

  const MemoryVisibility(this.value);
  final String value;

  static MemoryVisibility fromString(String s) =>
      MemoryVisibility.values.firstWhere(
        (v) => v.value == s,
        orElse: () => MemoryVisibility.public,
      );

  String get label {
    switch (this) {
      case MemoryVisibility.public:
        return 'Pubblico';
      case MemoryVisibility.circle:
        return 'Cerchia';
      case MemoryVisibility.private:
        return 'Privato';
    }
  }

  IconData get icon {
    switch (this) {
      case MemoryVisibility.public:
        return Icons.public_outlined;
      case MemoryVisibility.circle:
        return Icons.people_outline;
      case MemoryVisibility.private:
        return Icons.lock_outline;
    }
  }
}

enum MemoryMood {
  echo('echo'),
  love('love'),
  secret('secret'),
  dream('dream'),
  lost('lost'),
  food('food');

  const MemoryMood(this.value);
  final String value;

  static MemoryMood fromString(String s) => MemoryMood.values.firstWhere(
    (m) => m.value == s,
    orElse: () => MemoryMood.echo,
  );
}

extension MemoryMoodX on MemoryMood {
  Color get color {
    switch (this) {
      case MemoryMood.echo:
        return const Color(0xFF7EB8D4);
      case MemoryMood.love:
        return const Color(0xFFE8879C);
      case MemoryMood.secret:
        return const Color(0xFF9B8ADE);
      case MemoryMood.dream:
        return const Color(0xFFD4A847);
      case MemoryMood.lost:
        return const Color(0xFF5BC4B0);
      case MemoryMood.food:
        return const Color(0xFFE8943B);
    }
  }

  String get emoji {
    switch (this) {
      case MemoryMood.echo:
        return '📡';
      case MemoryMood.love:
        return '❤️';
      case MemoryMood.secret:
        return '🤫';
      case MemoryMood.dream:
        return '💫';
      case MemoryMood.lost:
        return '🌀';
      case MemoryMood.food:
        return '🍽️';
    }
  }

  String get label {
    switch (this) {
      case MemoryMood.echo:
        return 'Echo';
      case MemoryMood.love:
        return 'Love';
      case MemoryMood.secret:
        return 'Secret';
      case MemoryMood.dream:
        return 'Dream';
      case MemoryMood.lost:
        return 'Lost';
      case MemoryMood.food:
        return 'Food';
    }
  }
}

class MemoryModel {
  final String id;
  final String userId;
  final String description;
  final MemoryMood mood;
  final double latitude;
  final double longitude;
  final String? locationName;
  final String? imageUrl;
  final int likesCount;
  final bool isLikedByMe;
  final int commentsCount;
  final String? aiCaption;
  final MemoryVisibility visibility;
  final DateTime createdAt;
  final ProfileModel? author;

  // Used by map for discovery radius
  static const double discoveryRadius = 300.0;

  // Short title for map card
  String get title =>
      description.length > 42
          ? '${description.substring(0, 42)}…'
          : description;

  const MemoryModel({
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
    this.visibility = MemoryVisibility.public,
    required this.createdAt,
    this.author,
  });

  factory MemoryModel.fromJson(Map<String, dynamic> json) {
    ProfileModel? author;
    final profileRaw = json['profiles'];
    if (profileRaw is Map<String, dynamic>) {
      author = ProfileModel.fromJson(profileRaw);
    }

    return MemoryModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      description: json['description'] as String,
      mood: MemoryMood.fromString(json['mood'] as String? ?? 'echo'),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      locationName: json['location_name'] as String?,
      imageUrl: json['image_url'] as String?,
      likesCount: json['likes_count'] as int? ?? 0,
      isLikedByMe: json['is_liked_by_me'] as bool? ?? false,
      commentsCount: json['comments_count'] as int? ?? 0,
      aiCaption: json['ai_caption'] as String?,
      visibility: MemoryVisibility.fromString(
        json['visibility'] as String? ?? 'public',
      ),
      createdAt: DateTime.parse(json['created_at'] as String),
      author: author,
    );
  }

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
  };

  MemoryModel copyWith({
    String? id,
    String? userId,
    String? description,
    MemoryMood? mood,
    double? latitude,
    double? longitude,
    String? locationName,
    String? imageUrl,
    int? likesCount,
    bool? isLikedByMe,
    int? commentsCount,
    String? aiCaption,
    MemoryVisibility? visibility,
    DateTime? createdAt,
    ProfileModel? author,
  }) {
    return MemoryModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      description: description ?? this.description,
      mood: mood ?? this.mood,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationName: locationName ?? this.locationName,
      imageUrl: imageUrl ?? this.imageUrl,
      likesCount: likesCount ?? this.likesCount,
      isLikedByMe: isLikedByMe ?? this.isLikedByMe,
      commentsCount: commentsCount ?? this.commentsCount,
      aiCaption: aiCaption ?? this.aiCaption,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt ?? this.createdAt,
      author: author ?? this.author,
    );
  }
}
