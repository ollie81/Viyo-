import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/studio_character.dart';

/// A drama's structured story — see viyo_ai's drama_creator.py
/// PlotOut. Every field defaults to '' server-side too, so a series
/// with no story generated yet never surfaces as null here.
class DramaPlot {
  final String premise;
  final String mainConflict;
  final String characterMotivations;
  final String majorSecrets;
  final String emotionalTurningPoints;
  final String episodeProgression;
  // The exact moment every episode's scene 1 is built from — distinct
  // from [premise] (scene-setting) and from [cliffhanger] (the ending
  // beat). Written by GPT specifically for hook strength, not just a
  // theme — see drama_creator.py's _STORYBOARD_PROMPT.
  final String openingHook;
  final String cliffhanger;

  const DramaPlot({
    this.premise = '',
    this.mainConflict = '',
    this.characterMotivations = '',
    this.majorSecrets = '',
    this.emotionalTurningPoints = '',
    this.episodeProgression = '',
    this.openingHook = '',
    this.cliffhanger = '',
  });

  bool get isEmpty => premise.isEmpty && mainConflict.isEmpty && cliffhanger.isEmpty;

  factory DramaPlot.fromJson(Map<String, dynamic> json) => DramaPlot(
        premise: json['premise'] ?? '',
        mainConflict: json['main_conflict'] ?? '',
        characterMotivations: json['character_motivations'] ?? '',
        majorSecrets: json['major_secrets'] ?? '',
        emotionalTurningPoints: json['emotional_turning_points'] ?? '',
        episodeProgression: json['episode_progression'] ?? '',
        openingHook: json['opening_hook'] ?? '',
        cliffhanger: json['cliffhanger'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'premise': premise,
        'main_conflict': mainConflict,
        'character_motivations': characterMotivations,
        'major_secrets': majorSecrets,
        'emotional_turning_points': emotionalTurningPoints,
        'episode_progression': episodeProgression,
        'opening_hook': openingHook,
        'cliffhanger': cliffhanger,
      };
}

class DramaIdeaResult {
  final String title;
  final DramaPlot plot;
  final List<StudioCharacter> characters;
  final int pointsUsed;

  DramaIdeaResult({required this.title, required this.plot, required this.characters, required this.pointsUsed});
}

class DramaSetupResult {
  final String title;
  final String genre;
  final DramaPlot plot;
  final List<StudioCharacter> characters;
  final String? coverImageUrl;
  final bool setupConfirmed;
  final int episodeDurationSeconds;
  final String dramaAspectRatio;
  // Null = use the backend's default duration->scene-count curve
  // (built for ad pacing). Set = a drama that wants denser/sparser
  // pacing than that curve would pick — see _pickEpisodeSceneCount.
  final int? episodeSceneCount;
  final int pointsUsed;

  DramaSetupResult({
    required this.title,
    required this.genre,
    required this.plot,
    required this.characters,
    required this.coverImageUrl,
    required this.setupConfirmed,
    required this.episodeDurationSeconds,
    required this.dramaAspectRatio,
    this.episodeSceneCount,
    required this.pointsUsed,
  });

  factory DramaSetupResult.fromJson(Map<String, dynamic> json) => DramaSetupResult(
        title: json['title'] ?? '',
        genre: json['genre'] ?? 'Drama',
        plot: DramaPlot.fromJson(json['plot'] as Map<String, dynamic>? ?? const {}),
        characters: ((json['characters'] as List?) ?? [])
            .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
            .toList(),
        coverImageUrl: json['cover_image_url'] as String?,
        setupConfirmed: json['setup_confirmed'] == true,
        episodeDurationSeconds: (json['episode_duration_seconds'] as num?)?.toInt() ?? 30,
        dramaAspectRatio: json['drama_aspect_ratio'] ?? '9:16',
        episodeSceneCount: (json['episode_scene_count'] as num?)?.toInt(),
        pointsUsed: (json['points_used'] as num?)?.toInt() ?? 0,
      );
}

class DramaCoverResult {
  final String coverImageUrl;
  final int pointsUsed;
  DramaCoverResult({required this.coverImageUrl, required this.pointsUsed});
}

class DramaViewsResult {
  final String frontViewUrl;
  final String sideViewUrl;
  final String rearViewUrl;
  final String fourViewSheetUrl;
  final int pointsUsed;
  DramaViewsResult({
    required this.frontViewUrl,
    required this.sideViewUrl,
    required this.rearViewUrl,
    required this.fourViewSheetUrl,
    required this.pointsUsed,
  });
}

/// Talks to viyo_ai's drama_creator.py — the AI-assistant-driven "New
/// Drama" flow alongside Viyo Studio's existing paste-a-script one.
/// Same X-Admin-Key gate, same base URL, same request/error-handling
/// shape as studio_service.dart, on purpose — this is an extension of
/// the same admin tool, not a separate product.
class DramaCreatorService {
  static Map<String, String> _headers(String adminKey) => {
        'Content-Type': 'application/json',
        'X-Admin-Key': adminKey,
      };

  static const _base = '${AiBackendConstants.baseUrl}/api/v1/admin/drama-creator';

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }

  static Future<DramaIdeaResult> generateIdea(String adminKey, String seriesId, {required String ideaText, required String genre}) async {
    final res = await http.post(
      Uri.parse('$_base/$seriesId/idea'),
      headers: _headers(adminKey),
      body: jsonEncode({'idea_text': ideaText, 'genre': genre}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not develop that idea (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return DramaIdeaResult(
      title: data['title'] ?? '',
      plot: DramaPlot.fromJson(data['plot'] as Map<String, dynamic>? ?? const {}),
      characters: ((data['characters'] as List?) ?? [])
          .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      pointsUsed: (data['points_used'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<DramaPlot> updatePlot(String adminKey, String seriesId, DramaPlot plot) async {
    final res = await http.put(
      Uri.parse('$_base/$seriesId/plot'),
      headers: _headers(adminKey),
      body: jsonEncode(plot.toJson()),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save plot edits (${res.statusCode})');
    }
    return DramaPlot.fromJson(jsonDecode(res.body));
  }

  static Future<DramaSetupResult> getSetup(String adminKey, String seriesId) async {
    final res = await http.get(Uri.parse('$_base/$seriesId/setup'), headers: _headers(adminKey));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load this drama\'s setup (${res.statusCode})');
    }
    return DramaSetupResult.fromJson(jsonDecode(res.body));
  }

  static Future<DramaCoverResult> generateCover(String adminKey, String seriesId) async {
    final res = await http.post(Uri.parse('$_base/$seriesId/cover'), headers: _headers(adminKey));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate the cover (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return DramaCoverResult(coverImageUrl: data['cover_image_url'], pointsUsed: (data['points_used'] as num?)?.toInt() ?? 0);
  }

  static Future<DramaViewsResult> generateCharacterViews(String adminKey, String characterId) async {
    final res = await http.post(Uri.parse('$_base/character/$characterId/views'), headers: _headers(adminKey));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate the reference sheet (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return DramaViewsResult(
      frontViewUrl: data['front_view_url'],
      sideViewUrl: data['side_view_url'],
      rearViewUrl: data['rear_view_url'],
      fourViewSheetUrl: data['four_view_sheet_url'],
      pointsUsed: (data['points_used'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> updateEpisodeSettings(
    String adminKey,
    String seriesId, {
    int? episodeDurationSeconds,
    String? dramaAspectRatio,
    int? episodeSceneCount,
  }) async {
    final res = await http.put(
      Uri.parse('$_base/$seriesId/episode-settings'),
      headers: _headers(adminKey),
      body: jsonEncode({
        if (episodeDurationSeconds != null) 'episode_duration_seconds': episodeDurationSeconds,
        if (dramaAspectRatio != null) 'drama_aspect_ratio': dramaAspectRatio,
        if (episodeSceneCount != null) 'episode_scene_count': episodeSceneCount,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save episode settings (${res.statusCode})');
    }
  }

  static Future<int> confirmSetup(String adminKey, String seriesId) async {
    final res = await http.post(Uri.parse('$_base/$seriesId/confirm'), headers: _headers(adminKey));
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not confirm — finish every step above first (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['points_used'] as num?)?.toInt() ?? 0;
  }

  /// Returns the raw response — the caller just navigates to the
  /// existing Scenes screen afterward, which reloads these same
  /// persisted scenes itself (GET /series/{id}/episode/{n}/scenes),
  /// so there's no need to decode the full scene shape here too.
  static Future<void> generateStoryboard(String adminKey, String seriesId, {int episodeNumber = 1}) async {
    final res = await http.post(
      Uri.parse('$_base/$seriesId/storyboard'),
      headers: _headers(adminKey),
      body: jsonEncode({'episode_number': episodeNumber}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate the storyboard (${res.statusCode})');
    }
  }
}
