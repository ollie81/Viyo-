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
  /// Saved voice + matching lips (sync.so), once Viyo switches it on.
  final bool lipsyncAvailable;
  StudioAccount(this.balance, this.voices, this.packs, this.checkoutAvailable,
      [this.effects = const [], this.lipsyncAvailable = false]);
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
  bool autoMusic;
  /// Check every new scene picture with the vision model (included in its price).
  bool autoInspect;
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
        autoMusic = j['auto_music'] != false,
        autoInspect = j['auto_inspect'] != false,
        musicName = j['music_name'],
        musicVolume = (j['music_volume'] as num?)?.toDouble() ?? 0.25,
        imageQuality = j['image_quality'] ?? 'standard',
        productionStyle = j['production_style'] ?? 'pictures',
        seriesId = j['series_id'],
        coverUrl = j['cover_url'],
        covers = ((j['covers'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        storyBible = j['story_bible'] is Map && (j['story_bible'] as Map).isNotEmpty
            ? Map<String, dynamic>.from(j['story_bible'])
            : null;
  /// What Viyo's writers' room planned: premise, characters, beats, ending,
  /// and what the script doctor fixed. Null until a script is written.
  final Map<String, dynamic>? storyBible;
  /// 'video' (characters talk in moving clips) or 'pictures'.
  final String productionStyle;
  /// Set once a next episode has been made from this project (or this is one).
  final String? seriesId;
  /// The AI-made poster (title in the art, small Viyo mark in the corner).
  final String? coverUrl;
  /// Every cover made for this production: {id, url, is_main}, newest first.
  final List<Map<String, dynamic>> covers;
  bool get vertical => aspectRatio == '9:16';
}

/// One message in the assistant chat. Assistant messages can carry
/// proposals: changes the creator applies or dismisses.
class StudioChatMessage {
  final String id, role, content;
  final List<Map<String, dynamic>> proposals;
  final DateTime? createdAt;
  StudioChatMessage.fromJson(Map j)
      : id = j['id'],
        role = j['role'] ?? 'assistant',
        content = j['content'] ?? '',
        proposals = ((j['proposals'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
        createdAt = DateTime.tryParse(j['created_at'] ?? '');
  bool get mine => role == 'user';
}

/// A place or an object that looks the same in every scene.
class StudioElement {
  final String id, kind, name, description, status;
  final Map<String, String> details;
  final String? imageUrl;
  final bool hasImage;
  StudioElement.fromJson(Map j)
      : id = j['id'],
        kind = j['kind'] ?? 'prop',
        name = j['name'] ?? '',
        description = j['description'] ?? '',
        status = j['status'] ?? 'draft',
        details = ((j['details'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v')),
        imageUrl = j['image_url'],
        hasImage = j['has_image'] == true;
  bool get isPlace => kind == 'location';
}

/// One picture on a character's reference sheet.
class StudioView {
  final String view, label;
  /// missing / draft / approved / outdated (made from an older front view)
  final String status;
  final String? url;
  StudioView.fromJson(Map j)
      : view = j['view'],
        label = j['label'] ?? j['view'],
        status = j['status'] ?? 'missing',
        url = j['url'];
  bool get exists => status != 'missing';
}

/// What a character wears in part of the story. Clothing, shoes, accessories
/// and makeup change on their own; the face and body never do.
class StudioOutfit {
  static const parts = ['clothing', 'shoes', 'accessories', 'makeup'];
  static const partLabels = {'clothing': 'Clothing', 'shoes': 'Shoes', 'accessories': 'Accessories', 'makeup': 'Makeup'};

  final String id, characterId, name, description, status, reason;
  final Map<String, String> partValues;
  final bool isDefault, isTemporary, hasImage, imageOutdated;
  final List<String> suggestedScenes;
  final String? imageUrl;
  StudioOutfit.fromJson(Map j)
      : id = j['id'],
        characterId = j['character_id'] ?? '',
        name = j['name'] ?? '',
        description = j['description'] ?? '',
        status = j['status'] ?? 'saved',
        reason = j['reason'] ?? '',
        partValues = Map<String, String>.from((j['parts'] as Map?) ?? const {}),
        isDefault = j['is_default'] == true,
        isTemporary = j['is_temporary'] == true,
        hasImage = j['has_image'] == true,
        imageOutdated = j['image_outdated'] == true,
        suggestedScenes = ((j['suggested_scenes'] as List?) ?? []).map((e) => e.toString()).toList(),
        imageUrl = j['image_url'];

  /// "Clothing: …; Shoes: …" for a one-line summary.
  String get summary {
    final bits = [for (final k in parts) if ((partValues[k] ?? '').isNotEmpty) '${partLabels[k]}: ${partValues[k]}'];
    if (description.isNotEmpty) bits.insert(0, description);
    return bits.join(' · ');
  }
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
        portraitUrl = j['portrait_url'],
        identity = Map<String, dynamic>.from((j['identity'] as Map?) ?? const {}),
        identityLocked = j['identity_locked'] == true,
        identityVersion = (j['identity_version'] as num?)?.toInt() ?? 0,
        referenceViews = ((j['reference_views'] as List?) ?? []).map((e) => StudioView.fromJson(e as Map)).toList(),
        lockProblem = j['lock_problem'],
        guessedFields = ((j['guessed_fields'] as List?) ?? []).map((e) => e.toString()).toList(),
        outfits = ((j['outfits'] as List?) ?? []).map((e) => StudioOutfit.fromJson(e as Map)).toList(),
        outfitSuggestions = ((j['outfit_suggestions'] as List?) ?? []).map((e) => StudioOutfit.fromJson(e as Map)).toList(),
        outfitLibrary = ((j['outfit_library'] as List?) ?? []).map((e) => StudioOutfit.fromJson(e as Map)).toList();

  /// The permanent look: {"basic": {...}, "face": {...}, "body": {...}, "default_outfit": "..."}.
  final Map<String, dynamic> identity;
  final bool identityLocked;
  final int identityVersion;
  final List<StudioView> referenceViews;
  /// Why the identity can't be approved and locked yet (null = it can).
  final String? lockProblem;
  /// Details the AI chose itself ("face.eyes"), not yet checked by the creator.
  final List<String> guessedFields;
  final List<StudioOutfit> outfits;
  /// Suggested by the AI from the screenplay; nothing is used until accepted.
  final List<StudioOutfit> outfitSuggestions;
  /// Saved outfits from the series' other episodes, ready to reuse.
  final List<StudioOutfit> outfitLibrary;
  bool get hasSheet => referenceViews.any((v) => v.view == 'front_full' && v.exists);
  List<String> get missingViews => [for (final v in referenceViews) if (!v.exists) v.view];
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
  final String? imageUrl, videoUrl, audioUrl, lipsyncUrl;
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
        lipsyncUrl = j['lipsync_url'],
        audioSeconds = (j['audio_seconds'] as num?)?.toDouble(),
        hasImage = j['has_image'] == true,
        hasVideo = j['has_video'] == true,
        hasAudio = j['has_audio'] == true,
        sfx = ((j['sfx'] as List?) ?? []).map((e) => e.toString()).toList(),
        voiceOutdated = ((j['voice_outdated'] as List?) ?? []).map((e) => e.toString()).toList(),
        speech = j['speech'] ?? 'saved_voice',
        hasLipsync = j['has_lipsync'] == true,
        outfits = Map<String, String>.from((j['outfits'] as Map?) ?? const {}),
        outfitOverrides = ((j['outfit_overrides'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), Map<String, String>.from(v as Map))),
        camera = j['camera'] ?? 'auto',
        cameraUsed = j['camera_used'] ?? 'front',
        consistency = ((j['consistency'] as List?) ?? []).map((e) => e.toString()).toList(),
        locationId = j['location_id'],
        propIds = (j['props'] as List?)?.map((e) => e.toString()).toList(),
        locationUsed = j['location_used'] is Map ? '${(j['location_used'] as Map)['name']}' : null,
        propsUsed = ((j['props_used'] as List?) ?? []).map((e) => '${(e as Map)['name']}').toList(),
        madeWithReferences = ((j['made_with_references'] as List?) ?? []).map((e) => e.toString()).toList(),
        continuity = j['continuity'] is Map ? Map<String, dynamic>.from(j['continuity']) : const {},
        imageApproved = j['image_approved'] == true,
        inspection = j['inspection'] is Map ? Map<String, dynamic>.from(j['inspection']) : null,
        shots = ((j['shots'] as List?) ?? []).map((e) => StudioShot.fromJson(e as Map)).toList(),
        shotPlanApproved = j['shot_plan_approved'] == true;
  /// The director's camera shots for this scene, in order (empty = one picture/clip for the scene).
  final List<StudioShot> shots;
  /// The creator approved the shot plan: shots can be made and the film uses them.
  final bool shotPlanApproved;
  /// The creator approved this exact picture: it is never replaced until unapproved.
  final bool imageApproved;
  /// The latest picture check: {scores, problems, summary, needs_attention, correction, outdated}.
  final Map<String, dynamic>? inspection;
  /// The continuity director's record: how the scene starts and ends, who is
  /// where, and how it follows the scene before (`transition`).
  final Map<String, dynamic> continuity;
  String get startState => '${continuity['start_state'] ?? ''}';
  String get endState => '${continuity['end_state'] ?? ''}';
  String get transition => '${continuity['transition'] ?? ''}';
  /// Characters whose identity or outfit changed after this scene was made.
  final List<String> consistency;
  /// The chosen place (null = worked out from the heading) and objects (null = worked out from the text).
  final String? locationId;
  final List<String>? propIds;
  /// The place and objects this scene actually uses.
  final String? locationUsed;
  final List<String> propsUsed;
  /// The reference pictures the scene's picture or video was actually made with.
  final List<String> madeWithReferences;
  /// {character id: outfit id}; a character not listed keeps the outfit from the scene before.
  final Map<String, String> outfits;
  /// This scene only: {character id: {part: text}} on top of the chosen outfit.
  final Map<String, Map<String, String>> outfitOverrides;
  /// auto / close_up / front / side / back / full_body / wide, and what 'auto' worked out.
  final String camera, cameraUsed;
  final bool hasLipsync;
  /// Who speaks the lines: 'video_model' (in the clip) or 'saved_voice'.
  final String speech;
  bool get spokenInVideo => speech == 'video_model';
  /// Characters whose voice was changed after this scene was recorded.
  final List<String> voiceOutdated;
  bool get ready => hasImage || (mode == 'video' && hasVideo);
}

class StudioJob {
  final String id, kind, status;
  final String? sceneId, characterId, shotId, error;
  final int estimatedCredits, chargedCredits;
  final DateTime? createdAt;
  StudioJob.fromJson(Map j)
      : id = j['id'],
        kind = j['kind'],
        status = j['status'],
        sceneId = j['scene_id'],
        characterId = j['character_id'],
        shotId = j['shot_id'],
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
        createdAt = DateTime.tryParse(j['created_at'] ?? ''),
        postId = j['post_id'];
  /// The Viyo post this version became, once published.
  final String? postId;
  bool get published => postId != null;
}

/// One camera shot of a scene (studio_shots).
class StudioShot {
  final String id, sceneId, shotType, cameraAngle, cameraMovement, description, reason, status;
  final int position;
  final double durationSeconds;
  final String? imageUrl, videoUrl;
  final bool hasImage, hasVideo, approved;
  final List<Map<String, dynamic>> dialogue;
  StudioShot.fromJson(Map j)
      : id = j['id'],
        sceneId = j['scene_id'] ?? '',
        shotType = j['shot_type'] ?? 'medium',
        cameraAngle = j['camera_angle'] ?? '',
        cameraMovement = j['camera_movement'] ?? 'static',
        description = j['description'] ?? '',
        reason = j['reason'] ?? '',
        status = j['status'] ?? 'planned',
        position = (j['position'] as num?)?.toInt() ?? 0,
        durationSeconds = (j['duration_seconds'] as num?)?.toDouble() ?? 3,
        imageUrl = j['image_url'],
        videoUrl = j['video_url'],
        hasImage = j['has_image'] == true,
        hasVideo = j['has_video'] == true,
        approved = j['approved'] == true,
        dialogue = ((j['dialogue'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  static const labels = {
    'establishing_wide': 'Establishing wide',
    'wide_two_shot': 'Wide two-shot',
    'medium': 'Medium',
    'close_up': 'Close-up',
    'extreme_close_up': 'Extreme close-up',
    'over_the_shoulder': 'Over the shoulder',
    'reaction': 'Reaction',
    'pov': 'Point of view',
    'insert': 'Insert',
  };
  String get label => labels[shotType] ?? shotType;
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
        balance = StudioBalance.fromJson(j['balance']),
        production = j['production'] is Map ? Map<String, dynamic>.from(j['production']) : null,
        elements = ((j['elements'] as List?) ?? []).map((e) => StudioElement.fromJson(e as Map)).toList(),
        continuityIssues = ((j['continuity_issues'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  /// Problems between consecutive scenes: {scene, previous, scene_id, kind, severity, message, fix}.
  final List<Map<String, dynamic>> continuityIssues;
  /// The production's places and objects.
  final List<StudioElement> elements;
  /// The latest one-click production run with its progress, if any.
  final Map<String, dynamic>? production;
  bool get producing => production?['status'] == 'running';
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
      j['lipsync_available'] == true,
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

  /// Persistent story-assistant workspace for this creator-owned project.
  /// These routes are added by the companion viyo_ai assistant API PR.
  static Future<Map<String, dynamic>> assistantState(String projectId) async =>
      Map<String, dynamic>.from(await _send('GET', '/projects/$projectId/assistant'));

  static Future<Map<String, dynamic>> assistantGenerate(
    String projectId, {
    required String requestId,
    required int confirmCredits,
  }) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/assistant/generate', {
        'request_id': requestId,
        'confirm_credits': confirmCredits,
      }));

  static Future<void> assistantApprove(String projectId) async {
    await _send('POST', '/projects/$projectId/assistant/approve', {'confirm_story': true});
  }

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

  /// `extra`: portrait jobs only, {'views': [...]} or {'outfit_id': ...}.
  static Future<StudioEstimate> estimate(String projectId, String kind, [List<String> targets = const [],
      Map<String, dynamic> extra = const {}]) async =>
      StudioEstimate.fromJson(await _send('POST', '/projects/$projectId/estimate', {'kind': kind, 'target_ids': targets, ...extra}));

  static Future<StudioBalance> startJobs(String projectId, String kind, List<String> targets, String requestId,
      {bool confirmReplace = false, Map<String, dynamic> extra = const {}}) async {
    final j = await _send('POST', '/projects/$projectId/jobs',
        {'kind': kind, 'target_ids': targets, 'request_id': requestId, if (confirmReplace) 'confirm_replace': true, ...extra});
    return StudioBalance.fromJson(j['balance']);
  }

  // ------------------------------------------------ character identity

  static Future<void> updateIdentity(String characterId, Map<String, dynamic> identity) =>
      _send('PATCH', '/characters/$characterId/identity', {'identity': identity});

  static Future<void> approveView(String characterId, String view) =>
      _send('POST', '/characters/$characterId/views/$view/approve');

  static Future<void> lockIdentity(String characterId) => _send('POST', '/characters/$characterId/identity/lock');

  static Future<void> unlockIdentity(String characterId) => _send('POST', '/characters/$characterId/identity/unlock');

  static Future<void> addOutfit(String characterId, String name, String description,
          {Map<String, String> parts = const {}, bool temporary = false}) =>
      _send('POST', '/characters/$characterId/outfits',
          {'name': name, 'description': description, 'parts': parts, 'is_temporary': temporary});

  static Future<void> acceptOutfit(String outfitId, {bool useInSuggestedScenes = true}) =>
      _send('POST', '/outfits/$outfitId/accept', {'use_in_suggested_scenes': useInSuggestedScenes});

  static Future<void> importOutfit(String characterId, String outfitId) =>
      _send('POST', '/characters/$characterId/outfits/import', {'outfit_id': outfitId});

  static Future<void> updateOutfit(String outfitId, Map<String, dynamic> fields) => _send('PATCH', '/outfits/$outfitId', fields);

  static Future<void> deleteOutfit(String outfitId) => _send('DELETE', '/outfits/$outfitId');

  /// Posts a finished film to Viyo: an episode of the creator's drama, live now.
  /// coinPrice 0 = free to watch.
  static Future<Map<String, dynamic>> publishRender(String renderId, {required int coinPrice, String caption = ''}) async =>
      Map<String, dynamic>.from(await _send('POST', '/renders/$renderId/publish',
          {'coin_price': coinPrice, 'caption': caption, 'confirm': true}));

  // ------------------------------------------------ one-click production

  static Future<Map<String, dynamic>> productionQuote(String projectId, {bool sheets = true}) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/production/quote', {'sheets': sheets}));

  static Future<Map<String, dynamic>> startProduction(String projectId, {required int confirmCredits, bool sheets = true}) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/production',
          {'request_id': newRequestId(), 'confirm_credits': confirmCredits, 'sheets': sheets}));

  static Future<void> resumeProduction(String runId) => _send('POST', '/production/$runId/resume');

  static Future<void> cancelProduction(String runId) => _send('POST', '/production/$runId/cancel');

  // ------------------------------------------------ assistant chat

  static Future<Map<String, dynamic>> chatHistory(String projectId, {String? conversationId}) async =>
      Map<String, dynamic>.from(await _send('GET',
          '/projects/$projectId/assistant/chat${conversationId == null ? '' : '?conversation_id=$conversationId'}'));

  static Future<Map<String, dynamic>> chatSend(String projectId, String message, String requestId, {String? conversationId}) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/assistant/chat',
          {'message': message, 'request_id': requestId, if (conversationId != null) 'conversation_id': conversationId}));

  static Future<Map<String, dynamic>> chatNew(String projectId) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/assistant/chat/new'));

  static Future<Map<String, dynamic>> applyProposal(String messageId, int index) async =>
      Map<String, dynamic>.from(await _send('POST', '/assistant/messages/$messageId/proposals/$index/apply'));

  /// What the assistant remembers about this production: {memory: {category: [{id, text, source}]}, labels}.
  static Future<Map<String, dynamic>> assistantMemory(String projectId) async =>
      Map<String, dynamic>.from(await _send('GET', '/projects/$projectId/assistant/memory'));

  static Future<Map<String, dynamic>> rememberFact(String projectId, String category, String text) async =>
      Map<String, dynamic>.from(await _send('POST', '/projects/$projectId/assistant/memory', {'category': category, 'text': text}));

  static Future<Map<String, dynamic>> correctMemory(String projectId, String itemId, {String? text, String? category}) async =>
      Map<String, dynamic>.from(await _send('PATCH', '/projects/$projectId/assistant/memory/$itemId',
          {if (text != null) 'text': text, if (category != null) 'category': category}));

  static Future<Map<String, dynamic>> forgetMemory(String projectId, String itemId) async =>
      Map<String, dynamic>.from(await _send('DELETE', '/projects/$projectId/assistant/memory/$itemId'));

  static Future<void> setProposalStatus(String messageId, int index, String status) =>
      _send('POST', '/assistant/messages/$messageId/proposals/$index/status', {'status': status});

  // ------------------------------------------------ picture approval and versions

  static Future<void> approveImage(String sceneId, bool approved) =>
      _send('POST', '/scenes/$sceneId/approve-image', {'approved': approved});

  /// Every picture and video made for a scene: [{id, kind, url, created_at, current}].
  static Future<List<Map<String, dynamic>>> sceneVersions(String sceneId) async {
    final j = await _send('GET', '/scenes/$sceneId/versions');
    return ((j['versions'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<void> restoreVersion(String sceneId, String assetId) =>
      _send('POST', '/scenes/$sceneId/restore', {'asset_id': assetId});

  // ------------------------------------------------ camera shots

  static Future<void> updateShot(String shotId, Map<String, dynamic> fields) => _send('PATCH', '/shots/$shotId', fields);

  static Future<void> approveShotPlan(String sceneId, bool approved) =>
      _send('POST', '/scenes/$sceneId/shots/approve', {'approved': approved});

  static Future<void> approveShot(String shotId, bool approved) =>
      _send('POST', '/shots/$shotId/approve', {'approved': approved});

  // ------------------------------------------------ places and objects

  static Future<void> addElement(String projectId, String kind, String name, String description,
          {Map<String, String> details = const {}}) =>
      _send('POST', '/projects/$projectId/elements',
          {'kind': kind, 'name': name, 'description': description, 'details': details});

  static Future<void> updateElement(String id, Map<String, dynamic> fields) => _send('PATCH', '/elements/$id', fields);

  static Future<void> deleteElement(String id) => _send('DELETE', '/elements/$id');

  static Future<void> chooseCover(String projectId, String coverId) =>
      _send('POST', '/projects/$projectId/cover', {'cover_id': coverId});

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

  /// Starts the real provider test on the server (hard cap, admin only).
  static Future<String> adminStartLiveCheck(String adminKey) async {
    final j = await _admin('POST', '/admin/live-check', adminKey, {'confirm_spend': true, 'cap_usd': 5.0});
    return j['id'] as String;
  }

  static String liveCheckLink(String id) => '$_base/live-check/$id';

  static Future<Map<String, dynamic>> liveCheckReport(String id) async =>
      Map<String, dynamic>.from(await _send('GET', '/live-check/$id'));

  static Future<(StudioBalance, List<Map<String, dynamic>>)> credits() async {
    final j = await _send('GET', '/credits');
    return (StudioBalance.fromJson(j['balance']),
        ((j['history'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList());
  }
}
