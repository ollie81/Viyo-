/// One character present in a [StudioScene] — [characterId] is null
/// when the scene-split step couldn't match the script's speaker name
/// to a saved `series_characters` row (e.g. a typo or a character
/// that was never added to the cast).
class StudioSceneCharacterRef {
  final String? characterId;
  final String name;
  // Swaps out this character's locked costume (StudioCharacter.
  // costumeLock) for just this one scene — e.g. pajamas for a home
  // scene instead of their usual suit — without touching the
  // character's own lock, which every other scene they're in keeps
  // using unchanged. Empty means "use the locked default," same as
  // the character having no costume lock at all.
  final String costumeOverride;

  const StudioSceneCharacterRef({this.characterId, required this.name, this.costumeOverride = ''});

  factory StudioSceneCharacterRef.fromJson(Map<String, dynamic> json) => StudioSceneCharacterRef(
        characterId: json['character_id'] as String?,
        name: json['name'] ?? '',
        costumeOverride: json['costume_override'] ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'character_id': characterId, 'name': name, 'costume_override': costumeOverride};

  StudioSceneCharacterRef copyWith({String? characterId, String? name, String? costumeOverride}) =>
      StudioSceneCharacterRef(
        characterId: characterId ?? this.characterId,
        name: name ?? this.name,
        costumeOverride: costumeOverride ?? this.costumeOverride,
      );
}

/// One line of dialogue within a [StudioScene].
class StudioSceneLine {
  final String id;
  final int sortOrder;
  final String? characterId;
  final String characterName;
  final String text;
  final String? audioUrl;

  const StudioSceneLine({
    required this.id,
    required this.sortOrder,
    this.characterId,
    required this.characterName,
    required this.text,
    this.audioUrl,
  });

  factory StudioSceneLine.fromJson(Map<String, dynamic> json) => StudioSceneLine(
        id: json['id'],
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        characterId: json['character_id'] as String?,
        characterName: json['character_name'] ?? '',
        text: json['text'] ?? '',
        audioUrl: json['audio_url'] as String?,
      );

  StudioSceneLine copyWith({String? text, String? audioUrl, String? characterId, String? characterName}) =>
      StudioSceneLine(
        id: id,
        sortOrder: sortOrder,
        characterId: characterId ?? this.characterId,
        characterName: characterName ?? this.characterName,
        text: text ?? this.text,
        audioUrl: audioUrl ?? this.audioUrl,
      );
}

/// One scene of an episode — a location, a camera shot, who's present,
/// what's visually happening, and its dialogue lines. Saved
/// server-side as soon as the episode script is split (unlike Phase
/// 1's characters/locations, which stay draft-only until explicitly
/// saved), since this screen's own image/audio generation needs a
/// stable [id] to attach to from the start.
class StudioScene {
  final String id;
  final int sortOrder;
  final String? locationId;
  final String locationName;
  final String cameraShot;
  final List<StudioSceneCharacterRef> characters;
  final String visualDescription;
  final String? imageUrl;
  // Set once this scene has had the optional Veo upgrade — when
  // present, assembly uses this real generated clip for the scene
  // instead of the default Ken Burns zoom/pan on [imageUrl], so one
  // episode can freely mix video and still-image scenes.
  final String? videoUrl;
  final List<StudioSceneLine> lines;

  const StudioScene({
    required this.id,
    required this.sortOrder,
    this.locationId,
    required this.locationName,
    required this.cameraShot,
    required this.characters,
    required this.visualDescription,
    this.imageUrl,
    this.videoUrl,
    required this.lines,
  });

  factory StudioScene.fromJson(Map<String, dynamic> json) => StudioScene(
        id: json['id'],
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        locationId: json['location_id'] as String?,
        locationName: json['location_name'] ?? '',
        cameraShot: json['camera_shot'] ?? 'medium',
        characters: ((json['characters'] as List?) ?? [])
            .map((c) => StudioSceneCharacterRef.fromJson(c as Map<String, dynamic>))
            .toList(),
        visualDescription: json['visual_description'] ?? '',
        imageUrl: json['image_url'] as String?,
        videoUrl: json['video_url'] as String?,
        lines: ((json['lines'] as List?) ?? []).map((l) => StudioSceneLine.fromJson(l as Map<String, dynamic>)).toList(),
      );

  StudioScene copyWith({
    String? locationName,
    String? cameraShot,
    String? visualDescription,
    String? imageUrl,
    String? videoUrl,
    List<StudioSceneCharacterRef>? characters,
    List<StudioSceneLine>? lines,
  }) =>
      StudioScene(
        id: id,
        sortOrder: sortOrder,
        locationId: locationId,
        locationName: locationName ?? this.locationName,
        cameraShot: cameraShot ?? this.cameraShot,
        characters: characters ?? this.characters,
        visualDescription: visualDescription ?? this.visualDescription,
        imageUrl: imageUrl ?? this.imageUrl,
        videoUrl: videoUrl ?? this.videoUrl,
        lines: lines ?? this.lines,
      );

  StudioScene withLineAt(int index, StudioSceneLine line) {
    final updated = List<StudioSceneLine>.from(lines);
    updated[index] = line;
    return copyWith(lines: updated);
  }
}
