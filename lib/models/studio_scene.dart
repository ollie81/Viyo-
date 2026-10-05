/// One character present in a [StudioScene] — [characterId] is null
/// when the scene-split step couldn't match the script's speaker name
/// to a saved `series_characters` row (e.g. a typo or a character
/// that was never added to the cast).
class StudioSceneCharacterRef {
  final String? characterId;
  final String name;

  const StudioSceneCharacterRef({this.characterId, required this.name});

  factory StudioSceneCharacterRef.fromJson(Map<String, dynamic> json) => StudioSceneCharacterRef(
        characterId: json['character_id'] as String?,
        name: json['name'] ?? '',
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
        lines: ((json['lines'] as List?) ?? []).map((l) => StudioSceneLine.fromJson(l as Map<String, dynamic>)).toList(),
      );

  StudioScene copyWith({
    String? locationName,
    String? cameraShot,
    String? visualDescription,
    String? imageUrl,
    List<StudioSceneLine>? lines,
  }) =>
      StudioScene(
        id: id,
        sortOrder: sortOrder,
        locationId: locationId,
        locationName: locationName ?? this.locationName,
        cameraShot: cameraShot ?? this.cameraShot,
        characters: characters,
        visualDescription: visualDescription ?? this.visualDescription,
        imageUrl: imageUrl ?? this.imageUrl,
        lines: lines ?? this.lines,
      );

  StudioScene withLineAt(int index, StudioSceneLine line) {
    final updated = List<StudioSceneLine>.from(lines);
    updated[index] = line;
    return copyWith(lines: updated);
  }
}
