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
  final String genre;
  final DateTime createdAt;

  // 'ongoing' | 'completed' | null. Null until a `status` column
  // exists on `series` — read opportunistically (see fromJson) rather
  // than sent on insert: a PostgREST insert referencing a nonexistent
  // column fails the whole write, so createSeries deliberately never
  // includes this key. Every place this is displayed is gated on
  // `!= null`, so it stays invisible today and lights up automatically
  // once the column exists, no follow-up deploy required.
  final String? status;

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
    this.genre = kDefaultDramaGenre,
    required this.createdAt,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.episodeCount = 0,
    this.status,
  });

  factory Series.fromJson(Map<String, dynamic> json, {int episodeCount = 0}) => Series(
        id: json['id'],
        userId: json['user_id'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        coverImageUrl: json['cover_image_url'],
        coinPricePerEpisode: json['coin_price_per_episode'] ?? 20,
        genre: json['genre'] ?? kDefaultDramaGenre,
        createdAt: DateTime.parse(json['created_at']),
        authorUsername: json['profiles']?['username'],
        authorDisplayName: json['profiles']?['display_name'],
        authorAvatarUrl: json['profiles']?['avatar_url'],
        episodeCount: episodeCount,
        status: json['status'] as String?,
      );

  Series copyWith({int? episodeCount, String? coverImageUrl}) => Series(
        id: id,
        userId: userId,
        title: title,
        description: description,
        coverImageUrl: coverImageUrl ?? this.coverImageUrl,
        coinPricePerEpisode: coinPricePerEpisode,
        genre: genre,
        createdAt: createdAt,
        authorUsername: authorUsername,
        authorDisplayName: authorDisplayName,
        status: status,
        authorAvatarUrl: authorAvatarUrl,
        episodeCount: episodeCount ?? this.episodeCount,
      );
}

/// Fixed genre list a creator picks from when starting a new series —
/// kept as a flat list rather than a separate genres table, the same
/// tradeoff ModerationService.reportReasons already makes: no migration
/// access from this codebase to change one later, so a plain constant
/// list is what's actually maintainable. 'All' is a UI-only filter
/// value, never stored on a series itself.
/// How the Dramas tab's poster grid orders series: newest first, by
/// all-time engagement across a series' episodes, or by recent
/// engagement decayed by age (same "hot" shape PostService._hotScore
/// already uses for the home feed) — surfaces a series that's
/// suddenly getting attention over one that was merely popular once.
enum DramaSort { newest, popular, hot }

const kDefaultDramaGenre = 'Drama';
const kDramaGenres = <String>[
  kDefaultDramaGenre,
  'Revenge',
  'Romance',
  'Billionaire',
  'Werewolf',
  'Fantasy',
  'Hidden Identity',
  'Comedy',
  'Thriller',
  'Family',
  'Male Lead',
  'Female Lead',
  'LGBTQ+',
];

/// Episodes 1..freeEpisodeCount of every series are free to watch;
/// unlocking starts at episode freeEpisodeCount + 1. Mirrored from
/// viyo_ai's episodes.py (FREE_EPISODE_COUNT) — no single source of
/// truth across the two repos, same tradeoff already accepted for
/// coin costs elsewhere in this app.
const int kFreeEpisodeCount = 3;
