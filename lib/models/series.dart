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

  // What kind of title this is (see the kContentType* constants below)
  // and which way its video is shot. Both null until the content_type/
  // orientation columns exist on `series` — read opportunistically
  // (see fromJson) rather than sent unconditionally on insert, same
  // "inert until migrated" posture as `status` above. Null reads as
  // 'short_drama'/'vertical' everywhere (see the effective* getters)
  // so every series created before these columns existed keeps
  // behaving exactly as it always did.
  final String? contentType;
  final String? orientation;

  String get effectiveContentType => contentType ?? kContentTypeShortDrama;
  String get effectiveOrientation => orientation ?? kOrientationVertical;

  // A Movie/Short Film is one uploaded video, not a multi-episode
  // series — see kSingleAssetContentTypes for what that changes in the
  // upload flow and the paywall (episodes.py's _is_free_episode).
  bool get isSingleAsset => kSingleAssetContentTypes.contains(effectiveContentType);
  bool get isLandscape => effectiveOrientation == kOrientationLandscape;

  Series({
    required this.id,
    required this.userId,
    required this.title,
    this.description = '',
    this.coverImageUrl,
    this.coinPricePerEpisode = kDefaultEpisodeCoinPrice,
    this.genre = kDefaultDramaGenre,
    required this.createdAt,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.episodeCount = 0,
    this.status,
    this.contentType,
    this.orientation,
  });

  factory Series.fromJson(Map<String, dynamic> json, {int episodeCount = 0}) => Series(
        id: json['id'],
        userId: json['user_id'],
        title: json['title'] ?? '',
        description: json['description'] ?? '',
        coverImageUrl: json['cover_image_url'],
        coinPricePerEpisode: json['coin_price_per_episode'] ?? kDefaultEpisodeCoinPrice,
        genre: json['genre'] ?? kDefaultDramaGenre,
        createdAt: DateTime.parse(json['created_at']),
        authorUsername: json['profiles']?['username'],
        authorDisplayName: json['profiles']?['display_name'],
        authorAvatarUrl: json['profiles']?['avatar_url'],
        episodeCount: episodeCount,
        status: json['status'] as String?,
        contentType: json['content_type'] as String?,
        orientation: json['orientation'] as String?,
      );

  Series copyWith({
    int? episodeCount,
    String? coverImageUrl,
    String? status,
    String? title,
    String? description,
    String? genre,
    String? userId,
  }) =>
      Series(
        id: id,
        userId: userId ?? this.userId,
        title: title ?? this.title,
        description: description ?? this.description,
        coverImageUrl: coverImageUrl ?? this.coverImageUrl,
        coinPricePerEpisode: coinPricePerEpisode,
        genre: genre ?? this.genre,
        createdAt: createdAt,
        authorUsername: authorUsername,
        authorDisplayName: authorDisplayName,
        status: status ?? this.status,
        authorAvatarUrl: authorAvatarUrl,
        episodeCount: episodeCount ?? this.episodeCount,
        contentType: contentType,
        orientation: orientation,
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

// Content type ids stored on `series.content_type` — what kind of
// title this is. Drives three things: which genre list the upload
// screen offers (kDramaGenres vs kGeneralGenres below), whether it's a
// multi-episode series or a single uploaded video (see
// kSingleAssetContentTypes), and the paywall's free-episode carve-out
// (episodes.py's _is_free_episode — mirrored client-side same as
// every other cross-repo constant here).
const kContentTypeShortDrama = 'short_drama';
const kContentTypeSeries = 'series';
const kContentTypeMovie = 'movie';
const kContentTypeShortFilm = 'short_film';
const kContentTypeAiFilm = 'ai_film';

// Display order + label for the upload screen's content-type picker.
const Map<String, String> kContentTypeLabels = {
  kContentTypeShortDrama: 'Short Drama',
  kContentTypeSeries: 'Series',
  kContentTypeMovie: 'Movie',
  kContentTypeShortFilm: 'Short Film',
  kContentTypeAiFilm: 'AI Film',
};

// Movie and Short Film are a single uploaded video, not a multi-episode
// series: the upload screen skips the "pick an existing series /
// episode number" step for these and always starts a new title, and
// the backend never applies the first-N-episodes-free carve-out to
// them (there's no episode 4 to ever reach) — they're priced from the
// first watch, same as any already-unlocked episode.
const kSingleAssetContentTypes = {kContentTypeMovie, kContentTypeShortFilm};

const kOrientationVertical = 'vertical';
const kOrientationLandscape = 'landscape';

/// Genre list for every content type except Short Drama, which keeps
/// using kDramaGenres unchanged below — this app's whole existing
/// Dramas tab/genre-filter UI is built around that exact list, and
/// nothing about broadening Viyo's content model requires touching it.
const kGeneralGenres = <String>[
  'Action',
  'Drama',
  'Comedy',
  'Romance',
  'Thriller',
  'Horror',
  'Sci-Fi',
  'Fantasy',
  'Documentary',
  'Family',
];

/// Episodes 1..freeEpisodeCount of every series are free to watch;
/// unlocking starts at episode freeEpisodeCount + 1. Mirrored from
/// viyo_ai's episodes.py (FREE_EPISODE_COUNT) — no single source of
/// truth across the two repos, same tradeoff already accepted for
/// coin costs elsewhere in this app.
const int kFreeEpisodeCount = 3;

/// Discount applied when unlocking every remaining episode of a series
/// at once instead of one at a time (see SeriesService.unlockSeriesBundle).
/// Display-only here — the backend (episodes.py's BUNDLE_DISCOUNT) is
/// the actual source of truth for what gets charged, mirrored client-
/// side same as kFreeEpisodeCount already is.
const double kBundleDiscount = 0.20;

/// Fallback price used whenever a series/episode's real coin price
/// can't be read — a series created before coin_price_per_episode
/// existed, or a join that came back without it. Never displays or
/// charges 0 coins for a locked episode: a null/zero price would
/// otherwise mean "free to unlock" (see episodes.py's own matching
/// DEFAULT_EPISODE_COIN_PRICE fallback — mirrored, not shared, same
/// tradeoff as every other cross-repo constant here).
const int kDefaultEpisodeCoinPrice = 30;
