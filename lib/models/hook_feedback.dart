/// Result of a hook-strength check — a fast, narrow read on just the
/// opening line/frame, not the whole post. See AiService.analyzeHook.
class HookFeedback {
  final String verdict; // "strong" | "average" | "weak"
  final String reason;
  final List<String> rewrites;

  HookFeedback({
    required this.verdict,
    required this.reason,
    required this.rewrites,
  });

  factory HookFeedback.fromAiResponse(Map<String, dynamic> json) => HookFeedback(
        verdict: json['verdict'] ?? 'average',
        reason: json['reason'] ?? '',
        rewrites: List<String>.from(json['rewrites'] ?? const []),
      );
}
