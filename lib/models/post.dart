enum PostType { text, photo, video }

PostType postTypeFromString(String s) {
  switch (s) {
    case 'photo':
      return PostType.photo;
    case 'video':
      return PostType.video;
    default:
      return PostType.text;
  }
}

class Post {
  final String id;
  final String userId;
  final PostType postType;
  final String caption;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final int likeCount;
  final int commentCount;
  final bool isBoosted;
  final bool isPrivate;
  final bool isArchived;
  final bool isPinned;
  final DateTime createdAt;

  // Populated client-side after a join with `profiles` — not stored in the
  // posts table itself.
  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;
  final bool likedByMe;

  Post({
    required this.id,
    required this.userId,
    required this.postType,
    this.caption = '',
    this.mediaUrl,
    this.thumbnailUrl,
    this.durationSeconds,
    this.likeCount = 0,
    this.commentCount = 0,
    this.isBoosted = false,
    this.isPrivate = false,
    this.isArchived = false,
    this.isPinned = false,
    required this.createdAt,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.likedByMe = false,
  });

  factory Post.fromJson(Map<String, dynamic> json) => Post(
        id: json['id'],
        userId: json['user_id'],
        postType: postTypeFromString(json['post_type']),
        caption: json['caption'] ?? '',
        mediaUrl: json['media_url'],
        thumbnailUrl: json['thumbnail_url'],
        durationSeconds: json['duration_seconds'],
        likeCount: json['like_count'] ?? 0,
        commentCount: json['comment_count'] ?? 0,
        isBoosted: json['is_boosted'] ?? false,
        isPrivate: json['is_private'] ?? false,
        isArchived: json['is_archived'] ?? false,
        isPinned: json['is_pinned'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        authorUsername: json['profiles']?['username'],
        authorDisplayName: json['profiles']?['display_name'],
        authorAvatarUrl: json['profiles']?['avatar_url'],
        likedByMe: json['liked_by_me'] ?? false,
      );
}
