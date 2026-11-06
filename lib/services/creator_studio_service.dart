import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// Viyo Studio (for creators): AI dramas, episodes and films made scene by
/// scene and paid with Studio credits. See creator_studio.py on the backend,
/// which prices, checks ownership and charges everything server-side.

class StudioBalance {
  final int available, purchased, promotional, held;
  const StudioBalance({this.available = 0, this.purchased = 0, this.promotional = 0, this.held = 0});
  factory StudioBalance.fromJson(Map? j) => StudioBalance(
        available: (j?['available'] as num?)?.toInt() ?? 0,
        purchased: (j?['purchased'] as num?)?.toInt() ?? 0,
        promotional: (j?['promotional'] as num?)?.toInt() ?? 0,
        held: (j?['held'] as num?)?.toInt() ?? 0,
      );
}

class StudioVoice {
  final String name, gender, style;
  /// A short sample to listen to, when Viyo has made one for this voice.
  final String? sampleUrl;
  StudioVoice(this.name, this.gender, this.style, {this.sampleUrl});
}

class StudioPack {
  final String id, label;
  final int credits;
  final double priceUsd;
  StudioPack(this.id, this.label, this.credits, this.priceUsd);
}

class StudioEffect {
  final String id, label;
  final bool loops;
  StudioEffect(this.id, this.label, this.loops);
}

class StudioAccount {
  final StudioBalance balance;
  final List<StudioVoice> voices;
  final List<StudioPack> packs;
  final bool checkoutAvailable;
  final List<StudioEffect> effects;
  StudioAccount(this.balance, this.voices, this.packs, this.checkoutAvailable, [this.effects = const []]);
}

class StudioProjectSummary {
  final String id, title, logline, kind, aspectRatio, genre;
  final int sceneCount, scenesWithImages, renderCount;
  final String? thumbnailUrl;
  final DateTime? updatedAt;
  StudioProjectSummary.fromJson(Map j)
      : id = j['id'],
        title = j['title'] ?? 'Untitled',
        logline = j['logline'] ?? '',
        kind = j['kind'] ?? 'episode',
        aspectRatio = j['aspect_ratio'] ?? '9:16',
        genre = j['genre'] ?? '',
        sceneCount = (j['scene_count'] as num?)?.toInt() ?? 0,
        scenesWithImages = (j['scenes_with_images'] as num?)?.toInt() ?? 0,
        renderCount = (j['render_count'] as num?)?.toInt() ?? 0,
        thumbnailUrl = j['thumbnail_url'],
        updatedAt = DateTime.tryParse(j['updated_at'] ?? '');
}

class StudioProject {
  final String id;
  String title, logline, kind, aspectRatio, genre, visualStyle, language, script;
  int targetSeconds;
  bool captions;
  bool hasMusic;
  String? musicName;
  double musicVolume;
  String imageQuality;
  StudioProject.fromJson(Map j)
      : id = j['id'],
        title = j['title'] ?? '',
        logline = j['logline'] ?? '',
        kind = j['kind'] ?? 'episode',
        aspectRatio = j['aspect_ratio'] ?? '9:16',
        genre = j['genre'] ?? '',
        visualStyle = j['visual_style'] ?? '',
        language = j['language'] ?? 'English',
        script = j['script'] ?? '',
        targetSeconds = (j['target_seconds'] as num?)?.toInt() ?? 90,
        captions = j['captions'] ?? true,
        hasMusic = j['has_music'] == true,
        musicName = j['music_name'],
        musicVolume = (j['music_volume'] as num?)?.toDouble() ?? 0.25,
        imageQuality = j['image_quality'] ?? 'standard',
        productionStyle = j['production_style'] ?? 'pictures',
        seriesId = j['series_id'];
  /// 'video' (characters talk in moving clips) or 'pictures'.
  final String productionStyle;
  /// Set once a next episode has been made from this project (or this is one).
  final String? seriesId;
  bool get vertical => aspectRatio == '9:16';
}

class StudioCharacter {
  final String id;
  String name, description, voice, voiceStyle;
  final String? portraitUrl;
  /// True once a line has been recorded with this voice.
  final bool voiceLocked;
  /// Worked out by Viyo from the story, e.g. "young child".
  final String? ageLabel;
  final int? ageYears;
  /// cast / approximate / needs_voice / unsupported_language / manual
  final String voiceStatus;
  StudioCharacter.fromJson(Map j)
      : id = j['id'],
        name = j['name'] ?? '',
        description = j['description'] ?? '',
        voice = j['voice'] ?? '',
        voiceStyle = j['voice_style'] ?? '',
        voiceLocked = j['voice_locked'] == true,
        ageLabel = j['age_label'],
        ageYears = (j['age_years'] as num?)?.toInt(),
        voiceStatus = j['voice_status'] ?? ((j['voice'] ?? '') == '' ? 'needs_voice' : 'cast'),
        portraitUrl = j['portrait_url'];
}

class StudioLine {
  String character, text, emotion, delivery;
  StudioLine(this.character, this.text, [this.emotion = '', this.delivery = '']);
  Map<String, dynamic> toJson() => {
        'character': character,
        'text': text,
        if (emotion.trim().isNotEmpty) 'emotion': emotion.trim(),
        if (delivery.trim().isNotEmpty) 'delivery': delivery.trim(),
      };
}

class StudioScene {
  final String id;
  final int position;
  String heading, visual, mode;
  double durationSeconds;
  List<StudioLine> dialogue;
  List<String> sfx;
  final String? imageUrl, videoUrl, audioUrl;
  final double? audioSeconds;
  final bool hasImage, hasVideo, hasAudio;
  StudioScene.fromJson(Map j)
      : id = j['id'],
        position = (j['position'] as num?)?.toInt() ?? 0,
        heading = j['heading'] ?? '',
        visual = j['visual'] ?? '',
        mode = j['mode'] ?? 'still',
        durationSeconds = (j['duration_seconds'] as num?)?.toDouble() ?? 5,
        dialogue = ((j['dialogue'] as List?) ?? [])
            .map((d) => StudioLine((d['character'] ?? '') as String, (d['text'] ?? '') as String,
                (d['emotion'] ?? '') as String, (d['delivery'] ?? '') as String))
            .toList(),
        imageUrl = j['image_url'],
        videoUrl = j['video_url'],
        audioUrl = j['audio_url'],
        audioSeconds = (j['audio_seconds'] as num?)?.toDouble(),
        hasImage = j['has_image'] == true,
        hasVideo = j['has_video'] == true,
        hasAudio = j['has_audio'] == true,
        sfx = ((j['sfx'] as List?) ?? []).map((e) => e.toString()).toList(),
        voiceOutdated = ((j['voice_outdated'] as List?) ?? []).map((e) => e.toString()).toList(),
        speech = j['speech'] ?? 'saved_voice';
  /// Who speaks the lines: 'video_model' (in the clip) or 'saved_voice'.
  final String speech;
  bool get spokenInVideo => speech == 'video_model';
  /// Characters whose voice was changed after this scene was recorded.
  final List<String> voiceOutdated;
  bool get ready => hasImage || (mode == 'video' && hasVideo);
}

class StudioJob {
  final String id, kind, status;
  final String? sceneId, characterId, error;
  final int estimatedCredits, chargedCredits;
  final DateTime? createdAt;
  StudioJob.fromJson(Map j)
      : id = j['id'],
        kind = j['kind'],
        status = j['status'],
        sceneId = j['scene_id'],
        characterId = j['character_id'],
        error = j['error'],
        estimatedCredits = (j['estimated_credits'] as num?)?.toInt() ?? 0,
        chargedCredits = (j['charged_credits'] as num?)?.toInt() ?? 0,
        createdAt = DateTime.tryParse(j['created_at'] ?? '');
  bool get active => status == 'queued' || status == 'running';
}

class StudioRender {
  final String id, aspectRatio;
  final int version;
  final int? width, height, bytes;
  final double durationSeconds;
  final DateTime? createdAt;
  StudioRender.fromJson(Map j)
      : id = j['id'],
        aspectRatio = j['aspect_ratio'] ?? '9:16',
        version = (j['version'] as num).toInt(),
        width = (j['width'] as num?)?.toInt(),
        height = (j['height'] as num?)?.toInt(),
        bytes = (j['bytes'] as num?)?.toInt(),
        durationSeconds = (j['duration_seconds'] as num?)?.toDouble() ?? 0,
        createdAt = DateTime.tryParse(j['created_at'] ?? '');
}

class StudioProjectDetail {
  final StudioProject project;
  final List<StudioCharacter> characters;
  final List<StudioScene> scenes;
  final List<StudioRender> renders;
  final List<StudioJob> jobs;
  final StudioBalance balance;
  StudioProjectDetail.fromJson(Map j)
      : project = StudioProject.fromJson(j['project']),
        characters = ((j['characters'] as List?) ?? []).map((e) => StudioCharacter.fromJson(e)).toList(),
        scenes = ((j['scenes'] as List?) ?? []).map((e) => StudioScene.fromJson(e)).toList(),
        renders = ((j['renders'] as List?) ?? []).map((e) => StudioRender.fromJson(e)).toList(),
        jobs = ((j['jobs'] as List?) ?? []).map((e) => StudioJob.fromJson(e)).toList(),
        balance = StudioBalance.fromJson(j['balance']);
}

class StudioEstimate {
  final String kind;
  final int totalCredits, readyCount;
  final List<Map<String, dynamic>> items;
  final StudioBalance balance;
  final String? note;
  StudioEstimate.fromJson(Map j)
      : kind = j['kind'],
        totalCredits = (j['total_credits'] as num?)?.toInt() ?? 0,
        readyCount = (j['ready_count'] as num?)?.toInt() ?? 0,
        items = ((j['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList(),
        balance = StudioBalance.fromJson(j['balance']),
        note = j['note'];
  List<String> get blockedReasons =>
      items.map((i) => i['blocked']).whereType<String>().toSet().toList();
}

class StudioException implements Exception {
  final String message;
  final int status;
  StudioException(this.message, this.status);
  bool get notEnoughCredits => status == 402;
  /// The server wants the creator to confirm replacing existing scenes.
  bool get needsReplaceConfirm => status == 409 && code == 'confirm_replace';
  /// The character already speaks in recorded scenes: the change must be confirmed.
  bool get needsVoiceChangeConfirm => status == 409 && code == 'confirm_voice_change';
  String? code;
  @override
  String toString() => message;
}

class CreatorStudioService {
  static String get _base => '${AiBackendConstants.baseUrl}/api/v1/studio';
  static final _rnd = Random.secure();

  static Map<String, String> _headers() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  static String newRequestId() =>
      List.generate(16, (_) => _rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

  static Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = Uri.parse('$_base$path');
    final h = _headers();
    final payload = body == null ? null : jsonEncode(body);
    late http.Response res;
    try {
      res = await switch (method) {
        'GET' => http.get(uri, headers: h),
        'POST' => http.post(uri, headers: h, body: payload),
        'PATCH' => http.patch(uri, headers: h, body: payload),
        'DELETE' => http.delete(uri, headers: h),
        _ => throw ArgumentError(method),
      }
          .timeout(const Duration(seconds: 45));
    } catch (_) {
      throw StudioException("Couldn't reach Viyo. Check your connection and try again.", 0);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return res.body.isEmpty ? null : jsonDecode(res.body);
    }
    var message = 'Something went wrong (${res.statusCode}).';
    String? code;
    try {
      final d = jsonDecode(res.body)['detail'];
      if (d is String) message = d;
      if (d is Map && d['message'] is String) message = d['message'];
      if (d is Map && d['code'] is String) code = d['code'];
    } catch (_) {}
    throw StudioException(message, res.statusCode)..code = code;
  }

  static Future<StudioAccount> account() async {
    final j = await _send('GET', '/me');
    return StudioAccount(
      StudioBalance.fromJson(j['balance']),
      ((j['voices'] as List?) ?? []).map((v) => StudioVoice(v['name'], v['gender'], v['style'])).toList(),
      ((j['packs'] as List?) ?? [])
          .map((p) => StudioPack(p['id'], p['label'], (p['credits'] as num).toInt(), (p['price_usd'] as num).toDouble()))
          .toList(),
      j['checkout_available'] == true,
      ((j['sound_effects'] as List?) ?? [])
          .map((e) => StudioEffect(e['id'], e['label'], e['loops'] == true))
          .toList(),
    );
  }

  static Future<(StudioBalance, List<StudioProjectSummary>)> projects() async {
    final j = await _send('GET', '/projects');
    return (
      StudioBalance.fromJson(j['balance']),
      ((j['projects'] as List?) ?? []).map((p) => StudioProjectSummary.fromJson(p)).toList(),
    );
  }

  static Future<String> createProject(Map<String, dynamic> body) async =>
      (await _send('POST', '/projects', body))['id'] as String;

  static Future<StudioProjectDetail> project(String id) async =>
      StudioProjectDetail.fromJson(await _send('GET', '/projects/$id'));

  static Future<void> updateProject(String id, Map<String, dynamic> fields) => _send('PATCH', '/projects/$id', fields);

  static Future<void> archiveProject(String id) => _send('POST', '/projects/$id/archive');

  static Future<void> addCharacter(String projectId, String name, String description) =>
      _send('POST', '/projects/$projectId/characters', {'name': name, 'description': description});

  /// Returns the scene ids that were recorded with the old voice when the
  /// voice changed (empty otherwise). Throws a 409 StudioException with code
  /// `confirm_voice_change` when recorded lines exist and it isn't confirmed.
  static Future<List<String>> updateCharacter(String id, Map<String, dynamic> fields) async {
    final j = await _send('PATCH', '/characters/$id', fields);
    return ((j?['rerecord_scene_ids'] as List?) ?? []).map((e) => e.toString()).toList();
  }

  static Future<List<StudioVoice>> voices() async {
    final j = await _send('GET', '/voices');
    return ((j['voices'] as List?) ?? [])
        .map((v) => StudioVoice(v['name'], v['gender'], v['style'], sampleUrl: v['sample_url']))
        .toList();
  }

  /// A new episode with the same settings and cast (same voices and faces).
  static Future<String> nextEpisode(String projectId) async {
    final j = await _send('POST', '/projects/$projectId/next-episode');
    return j['id'] as String;
  }

  static Future<void> deleteCharacter(String id) => _send('DELETE', '/characters/$id');

  static Future<void> addScene(String projectId, {int? position}) =>
      _send('POST', '/projects/$projectId/scenes', {'heading': '', 'visual': '', if (position != null) 'position': position});

  static Future<void> updateScene(String id, Map<String, dynamic> fields) => _send('PATCH', '/scenes/$id', fields);

  static Future<void> deleteScene(String id) => _send('DELETE', '/scenes/$id');

  static Future<void> reorderScenes(String projectId, List<String> ids) =>
      _send('POST', '/projects/$projectId/scenes/order', {'scene_ids': ids});

  static Future<StudioEstimate> estimate(String projectId, String kind, [List<String> targets = const []]) async =>
      StudioEstimate.fromJson(await _send('POST', '/projects/$projectId/estimate', {'kind': kind, 'target_ids': targets}));

  static Future<StudioBalance> startJobs(String projectId, String kind, List<String> targets, String requestId,
      {bool confirmReplace = false}) async {
    final j = await _send('POST', '/projects/$projectId/jobs',
        {'kind': kind, 'target_ids': targets, 'request_id': requestId, if (confirmReplace) 'confirm_replace': true});
    return StudioBalance.fromJson(j['balance']);
  }

  static Future<(List<StudioJob>, StudioBalance)> jobs(String projectId) async {
    final j = await _send('GET', '/projects/$projectId/jobs');
    return (((j['jobs'] as List?) ?? []).map((e) => StudioJob.fromJson(e)).toList(), StudioBalance.fromJson(j['balance']));
  }

  static Future<void> cancelJob(String id) => _send('POST', '/jobs/$id/cancel');

  /// The creator's own background track (MP3, M4A or WAV, up to 25 MB).
  static Future<String> uploadMusic(String projectId, List<int> bytes, String fileName) async {
    final req = http.MultipartRequest('POST', Uri.parse('$_base/projects/$projectId/music'));
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields['rights_confirmed'] = 'true';
    req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    late http.Response res;
    try {
      res = await http.Response.fromStream(await req.send().timeout(const Duration(minutes: 3)));
    } catch (_) {
      throw StudioException("Couldn't upload the music. Check your connection and try again.", 0);
    }
    if (res.statusCode != 200) {
      var message = 'Upload failed (${res.statusCode}).';
      try {
        final d = jsonDecode(res.body)['detail'];
        if (d is String) message = d;
      } catch (_) {}
      throw StudioException(message, res.statusCode);
    }
    return (jsonDecode(res.body)['music_name'] as String?) ?? fileName;
  }

  static Future<void> removeMusic(String projectId) => _send('DELETE', '/projects/$projectId/music');

  static Future<(String, String)> renderLink(String renderId) async {
    final j = await _send('POST', '/renders/$renderId/download');
    return (j['url'] as String, j['file_name'] as String);
  }

  /// Admin only (X-Admin-Key): add credits to an account by @username or id.
  /// kind 'grant' = promotional (free); 'purchase' = paid outside the app.
  static Future<StudioBalance> adminGrant({
    required String adminKey,
    required String user,
    required int credits,
    required String kind,
    String note = '',
    double amountUsd = 0,
    String reference = '',
    int? expiresDays,
  }) async {
    final res = await http
        .post(Uri.parse('$_base/admin/credits/grant'),
            headers: {'Content-Type': 'application/json', 'X-Admin-Key': adminKey},
            body: jsonEncode({
              'user': user, 'credits': credits, 'kind': kind, 'note': note, 'amount_usd': amountUsd,
              'reference': reference, if (expiresDays != null) 'expires_days': expiresDays,
            }))
        .timeout(const Duration(seconds: 30));
    final body = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode != 200) {
      final d = body is Map ? body['detail'] : null;
      throw StudioException(d is String ? d : 'Could not add credits (${res.statusCode}).', res.statusCode);
    }
    if (body['duplicate'] == true) {
      throw StudioException('That reference was already used, so nothing was added again.', 409);
    }
    return StudioBalance.fromJson(body['balance']);
  }

  // ------------------------------------------------------------ admin voice gallery

  static Future<dynamic> _admin(String method, String path, String adminKey, [Object? body]) async {
    final uri = Uri.parse('$_base$path');
    final h = {'Content-Type': 'application/json', 'X-Admin-Key': adminKey};
    final res = await (switch (method) {
      'GET' => http.get(uri, headers: h),
      'PATCH' => http.patch(uri, headers: h, body: jsonEncode(body)),
      _ => http.post(uri, headers: h, body: jsonEncode(body)),
    })
        .timeout(const Duration(seconds: 120));
    final j = res.body.isEmpty ? {} : jsonDecode(res.body);
    if (res.statusCode != 200) {
      final d = j is Map ? j['detail'] : null;
      throw StudioException(d is String ? d : 'Something went wrong (${res.statusCode}).', res.statusCode);
    }
    return j;
  }

  static Future<Map<String, dynamic>> adminVoices(String adminKey) async =>
      Map<String, dynamic>.from(await _admin('GET', '/admin/voices', adminKey));

  static Future<void> adminUpdateVoice(String adminKey, String voiceId, Map<String, dynamic> fields) =>
      _admin('PATCH', '/admin/voices/google/$voiceId', adminKey, fields);

  /// Without [confirmSpend] nothing is made: it returns what would be made
  /// and the estimated cost.
  static Future<Map<String, dynamic>> adminMakeSamples(String adminKey, {bool confirmSpend = false}) async =>
      Map<String, dynamic>.from(
          await _admin('POST', '/admin/voices/samples', adminKey, {'confirm_spend': confirmSpend}));

  static Future<(StudioBalance, List<Map<String, dynamic>>)> credits() async {
    final j = await _send('GET', '/credits');
    return (StudioBalance.fromJson(j['balance']),
        ((j['history'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList());
  }
}
