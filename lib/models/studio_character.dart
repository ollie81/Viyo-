/// A character extracted from a script by Viyo Studio's "Analyze
/// Script" step — editable in the UI before being saved to a series,
/// and re-generatable (the portrait) independently of the others.
/// [id] is null until it's actually been saved (see StudioService.saveCast).
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
  });

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
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'age': age,
        'gender': gender,
        'appearance': appearance,
        'clothing': clothing,
        'personality': personality,
        'portrait_url': portraitUrl,
        'voice_id': voiceId,
        'costume_lock': costumeLock,
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
      );
}
