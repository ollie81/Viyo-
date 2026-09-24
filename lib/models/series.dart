/// An AI Short Drama series — episodes are ordinary video posts tagged
/// with this series' id + an episode number (see Post.seriesId /
/// Post.episodeNumber), not a separate content type of their own.
class Series {
  final String id;
  final String userId;
  final String title;
  final String description;
  final String? coverImageUrl;
  final int coinPricePerEpisode;
  final DateTime createdAt;

  // Populated client-side after a join with `profiles`, same as Post.
  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;

  // Populated client-side by whoever fetched this series — how many
  // episodes exist right now. Not a stored column (see the migration's
  // reasoning: computed, not cached, so it can never drift out of sync).
  final int episodeCount;

  Series({
    required this.id,
    required this.userId,
    required this.title,
    this.description = '',
    this.coverImageUrl,
    this.coinPricePerEpisode = 20,
    required this.createdAt,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.episodeCount = 0,
  });

  factory Series.fromJson(Map<String, dynamic> json, {int episodeCount = 0}) => Series(
        id: json['id'],
        userId: json['user_id'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        coverImageUrl: json['cover_image_url'],
        coinPricePerEpisode: json['coin_price_per_episode'] ?? 20,
        createdAt: DateTime.parse(json['created_at']),
        authorUsername: json['profiles']?['username'],
        authorDisplayName: json['profiles']?['display_name'],
        authorAvatarUrl: json['profiles']?['avatar_url'],
        episodeCount: episodeCount,
      );

  Series copyWith({int? episodeCount}) => Series(
        id: id,
        userId: userId,
        title: title,
        description: description,
        coverImageUrl: coverImageUrl,
        coinPricePerEpisode: coinPricePerEpisode,
        createdAt: createdAt,
        authorUsername: authorUsername,
        authorDisplayName: authorDisplayName,
        authorAvatarUrl: authorAvatarUrl,
        episodeCount: episodeCount ?? this.episodeCount,
      );
}

/// Episodes 1..freeEpisodeCount of every series are free to watch;
/// unlocking starts at episode freeEpisodeCount + 1. Mirrored from
/// viyo_ai's episodes.py (FREE_EPISODE_COUNT) — no single source of
/// truth across the two repos, same tradeoff already accepted for
/// coin costs elsewhere in this app.
const int kFreeEpisodeCount = 3;
