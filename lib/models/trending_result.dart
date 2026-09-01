class TrendingResult {
  final bool hasData;
  final String niche;
  final int sampleSize;
  final List<String> themes;
  final List<String> exampleCaptions;
  final String idea;

  TrendingResult({
    required this.hasData,
    required this.niche,
    required this.sampleSize,
    required this.themes,
    required this.exampleCaptions,
    required this.idea,
  });

  factory TrendingResult.fromJson(Map<String, dynamic> json) => TrendingResult(
        hasData: json['has_data'] == true,
        niche: json['niche'] as String? ?? '',
        sampleSize: (json['sample_size'] as num?)?.toInt() ?? 0,
        themes: List<String>.from(json['themes'] ?? const []),
        exampleCaptions: List<String>.from(json['example_captions'] ?? const []),
        idea: json['idea'] as String? ?? '',
      );
}
