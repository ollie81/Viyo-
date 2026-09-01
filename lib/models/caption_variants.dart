class CaptionVariants {
  final List<String> variants;
  // True when these variants were grounded in the creator's own
  // past above-average captions, false when they're generic (not
  // enough post history yet for personalization to mean anything).
  final bool personalized;

  CaptionVariants({required this.variants, required this.personalized});

  factory CaptionVariants.fromAiResponse(Map<String, dynamic> json) => CaptionVariants(
        variants: List<String>.from(json['variants'] ?? const []),
        personalized: json['personalized'] == true,
      );
}
