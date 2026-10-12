/// A character extracted from a script by Viyo Studio's "Analyze
/// Script" step — editable in the UI before being saved to a series,
/// and re-generatable (the portrait) independently of the others.
/// [id] is null until it's actually been saved (see StudioService.saveCast).
///
/// The fields from [skinTone] through [fourViewSheetUrl] are written
/// by the newer AI Drama Creator flow (drama_creator_service.dart) —
/// the original paste-a-script flow never sets them, which is fine:
/// the backend (studio.py's save_cast) preserves whatever's already
/// stored for a character when a save request leaves them blank,
/// specifically so editing an AI-assistant-created character from
/// this older screen never wipes them out.
class StudioCharacter {
  final String? id;
  final String name;
  final String age;
  final String gender;
  final String appearance;
  final String clothing;
  final String personality;
  final String? portraitUrl;
  final String? voiceId;
  // A fixed, verbatim costume description (e.g. "black designer suit
  // jacket, white shirt, black tie") reused as-is in every scene-image
  // prompt this character appears in — unlike [clothing] (a looser,
  // script-inferred wardrobe guess), this exists specifically to pin
  // one exact outfit across every scene so it doesn't visibly drift.
  // Empty is a real, supported choice (no lock), not a placeholder.
  final String costumeLock;
  final String skinTone;
  final String faceShape;
  final String eyeColor;
  final String hairstyle;
  final String bodyProportions;
  final String voiceDescription;
  final String? frontViewUrl;
  final String? sideViewUrl;
  final String? rearViewUrl;
  final String? fourViewSheetUrl;

  const StudioCharacter({
    this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.appearance,
    required this.clothing,
    required this.personality,
    this.portraitUrl,
    this.voiceId,
    this.costumeLock = '',
    this.skinTone = '',
    this.faceShape = '',
    this.eyeColor = '',
    this.hairstyle = '',
    this.bodyProportions = '',
    this.voiceDescription = '',
    this.frontViewUrl,
    this.sideViewUrl,
    this.rearViewUrl,
    this.fourViewSheetUrl,
  });

  bool get hasFourViewSheet => fourViewSheetUrl != null && fourViewSheetUrl!.isNotEmpty;

  factory StudioCharacter.fromJson(Map<String, dynamic> json) => StudioCharacter(
        id: json['id'] as String?,
        name: json['name'] ?? '',
        age: json['age'] ?? '',
        gender: json['gender'] ?? '',
        appearance: json['appearance'] ?? '',
        clothing: json['clothing'] ?? '',
        personality: json['personality'] ?? '',
        portraitUrl: json['portrait_url'] as String?,
        voiceId: json['voice_id'] as String?,
        costumeLock: json['costume_lock'] ?? '',
        skinTone: json['skin_tone'] ?? '',
        faceShape: json['face_shape'] ?? '',
        eyeColor: json['eye_color'] ?? '',
        hairstyle: json['hairstyle'] ?? '',
        bodyProportions: json['body_proportions'] ?? '',
        voiceDescription: json['voice_description'] ?? '',
        frontViewUrl: json['front_view_url'] as String?,
        sideViewUrl: json['side_view_url'] as String?,
        rearViewUrl: json['rear_view_url'] as String?,
        fourViewSheetUrl: json['four_view_sheet_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        // Present for an already-saved character so the backend can
        // update that same row in place instead of recreating it under
        // a new id — see StudioService.saveCast's own comment for why
        // that distinction matters (it's what scenes/dialogue lines
        // reference). Omitted (null) for one just extracted by Analyze
        // Script that's never been saved yet.
        if (id != null) 'id': id,
        'name': name,
        'age': age,
        'gender': gender,
        'appearance': appearance,
        'clothing': clothing,
        'personality': personality,
        'portrait_url': portraitUrl,
        'voice_id': voiceId,
        'costume_lock': costumeLock,
        'skin_tone': skinTone,
        'face_shape': faceShape,
        'eye_color': eyeColor,
        'hairstyle': hairstyle,
        'body_proportions': bodyProportions,
        'voice_description': voiceDescription,
        'front_view_url': frontViewUrl,
        'side_view_url': sideViewUrl,
        'rear_view_url': rearViewUrl,
        'four_view_sheet_url': fourViewSheetUrl,
      };

  StudioCharacter copyWith({
    String? name,
    String? age,
    String? gender,
    String? appearance,
    String? clothing,
    String? personality,
    String? portraitUrl,
    String? voiceId,
    String? costumeLock,
    String? skinTone,
    String? faceShape,
    String? eyeColor,
    String? hairstyle,
    String? bodyProportions,
    String? voiceDescription,
    String? frontViewUrl,
    String? sideViewUrl,
    String? rearViewUrl,
    String? fourViewSheetUrl,
  }) =>
      StudioCharacter(
        id: id,
        name: name ?? this.name,
        age: age ?? this.age,
        gender: gender ?? this.gender,
        appearance: appearance ?? this.appearance,
        clothing: clothing ?? this.clothing,
        personality: personality ?? this.personality,
        portraitUrl: portraitUrl ?? this.portraitUrl,
        voiceId: voiceId ?? this.voiceId,
        costumeLock: costumeLock ?? this.costumeLock,
        skinTone: skinTone ?? this.skinTone,
        faceShape: faceShape ?? this.faceShape,
        eyeColor: eyeColor ?? this.eyeColor,
        hairstyle: hairstyle ?? this.hairstyle,
        bodyProportions: bodyProportions ?? this.bodyProportions,
        voiceDescription: voiceDescription ?? this.voiceDescription,
        frontViewUrl: frontViewUrl ?? this.frontViewUrl,
        sideViewUrl: sideViewUrl ?? this.sideViewUrl,
        rearViewUrl: rearViewUrl ?? this.rearViewUrl,
        fourViewSheetUrl: fourViewSheetUrl ?? this.fourViewSheetUrl,
      );
}
