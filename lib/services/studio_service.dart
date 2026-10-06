import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/series.dart';
import '../models/studio_character.dart';
import '../models/studio_episode_status.dart';
import '../models/studio_location.dart';
import '../models/studio_scene.dart';
import '../models/studio_voice.dart';

/// Result of analyzing a script — not yet saved anywhere; the admin
/// edits these in memory, regenerates images, then calls
/// [StudioService.saveCast] once they're happy with it.
class ScriptAnalysisResult {
  final List<StudioCharacter> characters;
  final List<StudioLocation> locations;
  final int costUsdCents;

  ScriptAnalysisResult({required this.characters, required this.locations, required this.costUsdCents});
}

class StudioImageResult {
  final String imageUrl;
  final int costUsdCents;

  StudioImageResult({required this.imageUrl, required this.costUsdCents});
}

class StudioSpendToday {
  final int spentUsdCents;
  final int capUsdCents;

  StudioSpendToday({required this.spentUsdCents, required this.capUsdCents});

  double get spentUsd => spentUsdCents / 100;
  double get capUsd => capUsdCents / 100;
}

class StudioCastResult {
  final List<StudioCharacter> characters;
  final List<StudioLocation> locations;

  StudioCastResult({required this.characters, required this.locations});
}

/// Not persisted — the admin can audition as many voices as they like
/// before committing one via [StudioService.setCharacterVoice].
class StudioVoicePreviewResult {
  final String audioUrl;
  final int costUsdCents;

  StudioVoicePreviewResult({required this.audioUrl, required this.costUsdCents});
}

class StudioScenesResult {
  final List<StudioScene> scenes;
  final int costUsdCents;

  StudioScenesResult({required this.scenes, this.costUsdCents = 0});
}

class StudioAssembleResult {
  final String previewVideoUrl;
  final int durationSeconds;

  StudioAssembleResult({required this.previewVideoUrl, required this.durationSeconds});
}

class StudioPublishResult {
  final String postId;
  final String mediaUrl;
  final String videoStatus;

  StudioPublishResult({required this.postId, required this.mediaUrl, required this.videoStatus});
}

/// Talks to viyo_ai's studio.py — Viyo Studio's admin-only script,
/// casting and location-image endpoints, gated by the same shared
/// X-Admin-Key header every other admin surface in this app uses (see
/// AdminModerationService). The key lives only in memory for the
/// calling screen's lifetime — never written to disk.
class StudioService {
  static Map<String, String> _headers(String adminKey) => {
        'Content-Type': 'application/json',
        'X-Admin-Key': adminKey,
      };

  static Future<ScriptAnalysisResult> analyzeScript(String adminKey, String script) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/analyze-script'),
      headers: _headers(adminKey),
      body: jsonEncode({'script': script}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not analyze script (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ScriptAnalysisResult(
      characters: ((data['characters'] as List?) ?? [])
          .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      locations: ((data['locations'] as List?) ?? [])
          .map((l) => StudioLocation.fromJson(l as Map<String, dynamic>))
          .toList(),
      costUsdCents: (data['cost_usd_cents'] as num).toInt(),
    );
  }

  static Future<StudioImageResult> generateCharacterPortrait(String adminKey, StudioCharacter character) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/character/portrait'),
      headers: _headers(adminKey),
      body: jsonEncode({
        'name': character.name,
        'age': character.age,
        'gender': character.gender,
        'appearance': character.appearance,
        'clothing': character.clothing,
        'personality': character.personality,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate portrait (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioImageResult(imageUrl: data['image_url'], costUsdCents: (data['cost_usd_cents'] as num).toInt());
  }

  static Future<StudioImageResult> generateLocationImage(String adminKey, StudioLocation location) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/location/image'),
      headers: _headers(adminKey),
      body: jsonEncode({
        'name': location.name,
        'description': location.description,
        'time_of_day': location.timeOfDay,
        'mood': location.mood,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate location image (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioImageResult(imageUrl: data['image_url'], costUsdCents: (data['cost_usd_cents'] as num).toInt());
  }

  /// Replaces the series' entire saved cast with [characters]/[locations]
  /// — see studio.py's own comment on why this is delete+insert rather
  /// than a partial upsert in Phase 1.
  static Future<ScriptAnalysisResult> saveCast(
    String adminKey,
    String seriesId, {
    required List<StudioCharacter> characters,
    required List<StudioLocation> locations,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/cast'),
      headers: _headers(adminKey),
      body: jsonEncode({
        'characters': characters.map((c) => c.toJson()).toList(),
        'locations': locations.map((l) => l.toJson()).toList(),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save cast (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ScriptAnalysisResult(
      characters: ((data['characters'] as List?) ?? [])
          .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      locations: ((data['locations'] as List?) ?? [])
          .map((l) => StudioLocation.fromJson(l as Map<String, dynamic>))
          .toList(),
      costUsdCents: 0,
    );
  }

  /// Reads back a series' already-saved cast — used by the Voices
  /// screen (Phase 2), which operates on persisted character rows
  /// rather than the in-memory draft the Analyze/Save flow (Phase 1)
  /// works with.
  static Future<StudioCastResult> getCast(String adminKey, String seriesId) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/cast'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load cast (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioCastResult(
      characters: ((data['characters'] as List?) ?? [])
          .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
          .toList(),
      locations: ((data['locations'] as List?) ?? [])
          .map((l) => StudioLocation.fromJson(l as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Renames/edits a drama's title, description or genre. Routed
  /// through this admin-gated backend endpoint rather than a direct
  /// Supabase update: `series`' update policy is owner-only, and a
  /// drama shown in Studio may well have been created under a
  /// different session than whoever's running Studio today, which
  /// would make a direct client write silently no-op (0 rows matched).
  static Future<Series> updateDramaDetails(
    String adminKey,
    Series current, {
    required String title,
    required String description,
    required String genre,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/${current.id}/details'),
      headers: _headers(adminKey),
      body: jsonEncode({'title': title, 'description': description, 'genre': genre}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save drama details (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return current.copyWith(
      title: data['title'] as String?,
      description: data['description'] as String?,
      genre: data['genre'] as String?,
    );
  }

  static Future<List<StudioVoice>> listVoices(String adminKey) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/voices'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load voices (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ((data['voices'] as List?) ?? []).map((v) => StudioVoice.fromJson(v as Map<String, dynamic>)).toList();
  }

  static Future<StudioVoicePreviewResult> previewVoice(
    String adminKey,
    String characterId,
    String voiceName, {
    String? sampleText,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/character/$characterId/voice-preview'),
      headers: _headers(adminKey),
      body: jsonEncode({
        'voice_name': voiceName,
        if (sampleText != null && sampleText.isNotEmpty) 'sample_text': sampleText,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not preview voice (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioVoicePreviewResult(
      audioUrl: data['audio_url'],
      costUsdCents: (data['cost_usd_cents'] as num).toInt(),
    );
  }

  /// Persists [voiceName] as this character's permanent voice — unlike
  /// [previewVoice], this is what every future episode's dialogue
  /// audio (Phase 3) will read back.
  static Future<void> setCharacterVoice(String adminKey, String characterId, String voiceName) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/character/$characterId/voice'),
      headers: _headers(adminKey),
      body: jsonEncode({'voice_name': voiceName}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save voice (${res.statusCode})');
    }
  }

  /// Free local-heuristic auto-assignment for every character in the
  /// series that doesn't already have a voice — no Gemini call, no
  /// cost. Returns the full updated cast.
  static Future<List<StudioCharacter>> assignVoices(String adminKey, String seriesId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/assign-voices'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not auto-assign voices (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ((data['characters'] as List?) ?? [])
        .map((c) => StudioCharacter.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  static Future<StudioSpendToday> spendToday(String adminKey) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/spend-today'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load Studio spend (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioSpendToday(
      spentUsdCents: (data['spent_usd_cents'] as num).toInt(),
      capUsdCents: (data['cap_usd_cents'] as num).toInt(),
    );
  }

  /// Splits one specific episode's script into saved scenes and
  /// dialogue lines — unlike analyzeScript (Phase 1), this persists
  /// immediately (see studio.py's split_scenes docstring) rather than
  /// returning a draft the admin saves later.
  static Future<StudioScenesResult> splitScenes(
    String adminKey,
    String seriesId,
    int episodeNumber,
    String script,
  ) async {
    final res = await http.post(
      Uri.parse(
        '${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/episode/$episodeNumber/split-scenes',
      ),
      headers: _headers(adminKey),
      body: jsonEncode({'script': script}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not split scenes (${res.statusCode})');
    }
    return _scenesResultFromResponse(res);
  }

  static Future<StudioScenesResult> getScenes(String adminKey, String seriesId, int episodeNumber) async {
    final res = await http.get(
      Uri.parse(
        '${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/episode/$episodeNumber/scenes',
      ),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load scenes (${res.statusCode})');
    }
    return _scenesResultFromResponse(res);
  }

  static StudioScenesResult _scenesResultFromResponse(http.Response res) {
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioScenesResult(
      scenes: ((data['scenes'] as List?) ?? []).map((s) => StudioScene.fromJson(s as Map<String, dynamic>)).toList(),
      costUsdCents: (data['cost_usd_cents'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<StudioScene> editScene(
    String adminKey,
    String sceneId, {
    String? visualDescription,
    String? cameraShot,
    String? locationName,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/scene/$sceneId/edit'),
      headers: _headers(adminKey),
      body: jsonEncode({
        if (visualDescription != null) 'visual_description': visualDescription,
        if (cameraShot != null) 'camera_shot': cameraShot,
        if (locationName != null) 'location_name': locationName,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save scene edit (${res.statusCode})');
    }
    return StudioScene.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<StudioImageResult> generateSceneImage(String adminKey, String sceneId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/scene/$sceneId/image'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate scene image (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioImageResult(imageUrl: data['image_url'], costUsdCents: (data['cost_usd_cents'] as num).toInt());
  }

  static Future<StudioSceneLine> editLine(
    String adminKey,
    String lineId, {
    String? text,
    String? characterId,
    String? characterName,
  }) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/line/$lineId/edit'),
      headers: _headers(adminKey),
      body: jsonEncode({
        if (text != null) 'text': text,
        if (characterId != null) 'character_id': characterId,
        if (characterName != null) 'character_name': characterName,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not save line edit (${res.statusCode})');
    }
    return StudioSceneLine.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  static Future<StudioVoicePreviewResult> generateLineAudio(String adminKey, String lineId) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/line/$lineId/audio'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not generate line audio (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioVoicePreviewResult(
      audioUrl: data['audio_url'],
      costUsdCents: (data['cost_usd_cents'] as num).toInt(),
    );
  }

  /// Renders this episode's scenes into one 9:16 MP4 and uploads it for
  /// preview — doesn't touch Bunny or publish anything yet. [musicUrl]
  /// is optional and admin-supplied (a track they already have the
  /// rights to use); omit it for no background music.
  static Future<StudioAssembleResult> assembleEpisode(
    String adminKey,
    String seriesId,
    int episodeNumber, {
    String? musicUrl,
  }) async {
    final res = await http.post(
      Uri.parse(
        '${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/episode/$episodeNumber/assemble',
      ),
      headers: _headers(adminKey),
      body: jsonEncode({if (musicUrl != null && musicUrl.isNotEmpty) 'music_url': musicUrl}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not assemble episode (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioAssembleResult(
      previewVideoUrl: data['preview_video_url'],
      durationSeconds: (data['duration_seconds'] as num).toInt(),
    );
  }

  /// Pushes the already-assembled preview to Bunny Stream and creates
  /// the real episode post — this is the actual "go live" action.
  static Future<StudioPublishResult> publishEpisode(
    String adminKey,
    String seriesId,
    int episodeNumber, {
    required String previewVideoUrl,
    required int durationSeconds,
    String? caption,
  }) async {
    final res = await http.post(
      Uri.parse(
        '${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/episode/$episodeNumber/publish',
      ),
      headers: _headers(adminKey),
      body: jsonEncode({
        'preview_video_url': previewVideoUrl,
        'duration_seconds': durationSeconds,
        if (caption != null && caption.isNotEmpty) 'caption': caption,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not publish episode (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return StudioPublishResult(
      postId: data['post_id'],
      mediaUrl: data['media_url'],
      videoStatus: data['video_status'],
    );
  }

  /// Per-episode Studio progress (scenes split / images done / audio
  /// done / published) for the home screen's status badges.
  static Future<List<StudioEpisodeStatus>> getEpisodeStatuses(String adminKey, String seriesId) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/studio/series/$seriesId/episodes'),
      headers: _headers(adminKey),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load episode status (${res.statusCode})');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return ((data['episodes'] as List?) ?? [])
        .map((e) => StudioEpisodeStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }
}
