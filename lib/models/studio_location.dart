/// A location extracted from a script by Viyo Studio's "Analyze
/// Script" step — editable in the UI before being saved to a series,
/// and re-generatable (the reference image) independently of the
/// others. [id] is null until it's actually been saved (see
/// StudioService.saveCast).
class StudioLocation {
  final String? id;
  final String name;
  final String description;
  final String timeOfDay;
  final String mood;
  final String? referenceImageUrl;

  const StudioLocation({
    this.id,
    required this.name,
    required this.description,
    required this.timeOfDay,
    required this.mood,
    this.referenceImageUrl,
  });

  factory StudioLocation.fromJson(Map<String, dynamic> json) => StudioLocation(
        id: json['id'] as String?,
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        timeOfDay: json['time_of_day'] ?? '',
        mood: json['mood'] ?? '',
        referenceImageUrl: json['reference_image_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'time_of_day': timeOfDay,
        'mood': mood,
        'reference_image_url': referenceImageUrl,
      };

  StudioLocation copyWith({
    String? name,
    String? description,
    String? timeOfDay,
    String? mood,
    String? referenceImageUrl,
  }) =>
      StudioLocation(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        timeOfDay: timeOfDay ?? this.timeOfDay,
        mood: mood ?? this.mood,
        referenceImageUrl: referenceImageUrl ?? this.referenceImageUrl,
      );
}
