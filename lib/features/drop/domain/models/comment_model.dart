import 'package:echo/features/profile/domain/models/profile_model.dart';

class CommentModel {
  final String id;
  final String dropId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final ProfileModel? author;

  const CommentModel({
    required this.id,
    required this.dropId,
    required this.userId,
    required this.content,
    required this.createdAt,
    this.author,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    ProfileModel? author;
    final raw = json['profiles'];
    if (raw is Map<String, dynamic>) {
      author = ProfileModel.fromJson(raw);
    }
    return CommentModel(
      id: json['id'] as String,
      dropId: json['memory_id'] as String,
      userId: json['user_id'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      author: author,
    );
  }
}
