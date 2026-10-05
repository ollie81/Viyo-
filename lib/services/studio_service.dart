import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';
import '../models/studio_character.dart';
import '../models/studio_location.dart';

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
