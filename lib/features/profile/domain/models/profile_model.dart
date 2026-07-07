class ProfileModel {
  final String id;
  final String username;
  final String displayName;
  final String bio;
  final String? avatarUrl;
  final int dropsCount;
  final int connectionsCount;
  final DateTime createdAt;
  final double? distanceKm;
  final DateTime? usernameChangedAt;

  const ProfileModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.bio = '',
    this.avatarUrl,
    this.dropsCount = 0,
    this.connectionsCount = 0,
    required this.createdAt,
    this.distanceKm,
    this.usernameChangedAt,
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
      dropsCount: json['memories_count'] as int? ?? 0,
      connectionsCount: json['connections_count'] as int? ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      usernameChangedAt: json['username_changed_at'] != null
          ? DateTime.parse(json['username_changed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'display_name': displayName,
    'bio': bio,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };

  Map<String, dynamic> toCacheJson() => {
    'id': id,
    'username': username,
    'display_name': displayName,
    'bio': bio,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
    'memories_count': dropsCount,
    'connections_count': connectionsCount,
    'created_at': createdAt.toIso8601String(),
  };

  ProfileModel copyWith({
    String? id,
    String? username,
    String? displayName,
    String? bio,
    String? avatarUrl,
    int? dropsCount,
    int? connectionsCount,
    DateTime? createdAt,
    double? distanceKm,
    DateTime? usernameChangedAt,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      dropsCount: dropsCount ?? this.dropsCount,
      connectionsCount: connectionsCount ?? this.connectionsCount,
      createdAt: createdAt ?? this.createdAt,
      distanceKm: distanceKm ?? this.distanceKm,
      usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
    );
  }
}
