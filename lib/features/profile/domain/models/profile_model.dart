class ProfileModel {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final int memoriesCount;
  final int connectionsCount;
  final DateTime createdAt;
  final double? distanceKm;

  const ProfileModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.memoriesCount = 0,
    this.connectionsCount = 0,
    required this.createdAt,
    this.distanceKm,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      username: json['username'] as String? ?? '',
      displayName:
          json['display_name'] as String? ??
          json['username'] as String? ??
          '',
      bio: json['bio'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      memoriesCount: json['memories_count'] as int? ?? 0,
      connectionsCount: json['connections_count'] as int? ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'bio': bio,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };

  ProfileModel copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    int? memoriesCount,
    int? connectionsCount,
    DateTime? createdAt,
    double? distanceKm,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      memoriesCount: memoriesCount ?? this.memoriesCount,
      connectionsCount: connectionsCount ?? this.connectionsCount,
      createdAt: createdAt ?? this.createdAt,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }
}
