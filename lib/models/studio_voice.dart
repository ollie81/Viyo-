/// One entry in Gemini's prebuilt TTS voice catalog, as returned by
/// GET /api/v1/admin/studio/voices — used both to show the admin a
/// human-readable picker and, client-side, to group that picker by
/// gender/age the same way the backend's own auto-assign heuristic does.
class StudioVoice {
  final String name;
  final String gender;
  final String age;
  final String description;

  const StudioVoice({
    required this.name,
    required this.gender,
    required this.age,
    required this.description,
  });

  factory StudioVoice.fromJson(Map<String, dynamic> json) => StudioVoice(
        name: json['name'] ?? '',
        gender: json['gender'] ?? '',
        age: json['age'] ?? '',
        description: json['description'] ?? '',
      );
}
