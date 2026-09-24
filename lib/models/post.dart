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
  final int viewCount;
  final bool isBoosted;
  final bool isPrivate;
  final bool isArchived;
  final bool isPinned;
  final DateTime createdAt;

  // AI Short Drama support. seriesId set at all is what makes this
  // post an episode rather than a plain photo/video — there is
  // deliberately no separate is_ai_drama flag (see the SQL migration).
  final String? seriesId;
  final int? episodeNumber;
  // Populated client-side after a join with `series` — not stored on
  // posts itself, same as the author fields below.
  final String? seriesTitle;
  final int? seriesCoinPrice;

  // Populated client-side after a join with `profiles` — not stored in the
  // posts table itself.
  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;
  final bool likedByMe;

  // Populated client-side from a separate episode_unlocks query (see
  // SeriesService.withUnlockState) — never trust a client-set value of
  // this for anything that gates real access; the paywall check re-runs
  // server-side in episodes.py regardless of what this says.
  final bool unlockedByMe;

  bool get isEpisode => seriesId != null;

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
    this.viewCount = 0,
    this.isBoosted = false,
    this.isPrivate = false,
    this.isArchived = false,
    this.isPinned = false,
    required this.createdAt,
    this.seriesId,
    this.episodeNumber,
    this.seriesTitle,
    this.seriesCoinPrice,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.likedByMe = false,
    this.unlockedByMe = false,
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
        viewCount: json['view_count'] ?? 0,
        isBoosted: json['is_boosted'] ?? false,
        isPrivate: json['is_private'] ?? false,
        isArchived: json['is_archived'] ?? false,
        isPinned: json['is_pinned'] ?? false,
        createdAt: DateTime.parse(json['created_at']),
        seriesId: json['series_id'],
        episodeNumber: json['episode_number'],
        seriesTitle: json['series']?['title'],
        seriesCoinPrice: json['series']?['coin_price_per_episode'],
        authorUsername: json['profiles']?['username'],
        authorDisplayName: json['profiles']?['display_name'],
        authorAvatarUrl: json['profiles']?['avatar_url'],
        likedByMe: json['liked_by_me'] ?? false,
        unlockedByMe: json['unlocked_by_me'] ?? false,
      );
  Post copyWith({
    String? id,
    String? userId,
    PostType? postType,
    String? caption,
    String? mediaUrl,
    String? thumbnailUrl,
    int? durationSeconds,
    int? likeCount,
    int? commentCount,
    int? viewCount,
    bool? isBoosted,
    bool? isPrivate,
    bool? isArchived,
    bool? isPinned,
    DateTime? createdAt,
    String? seriesId,
    int? episodeNumber,
    String? authorUsername,
    String? authorDisplayName,
    String? authorAvatarUrl,
    bool? likedByMe,
    bool? unlockedByMe,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      postType: postType ?? this.postType,
      caption: caption ?? this.caption,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      isBoosted: isBoosted ?? this.isBoosted,
      isPrivate: isPrivate ?? this.isPrivate,
      isArchived: isArchived ?? this.isArchived,
      isPinned: isPinned ?? this.isPinned,
      createdAt: createdAt ?? this.createdAt,
      seriesId: seriesId ?? this.seriesId,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      authorUsername: authorUsername ?? this.authorUsername,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      likedByMe: likedByMe ?? this.likedByMe,
      unlockedByMe: unlockedByMe ?? this.unlockedByMe,
    );
  }
}
