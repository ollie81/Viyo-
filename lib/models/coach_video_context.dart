/// What the AI Coach can actually see about the video being discussed.
///
/// Until this existed the Coach was blind — the backend received a
/// video_id and used it only to partition chat history, so every answer
/// was generic advice about a video it had never seen, at real coins per
/// message. For a posted video the backend resolves the real numbers
/// itself; this carries the part it cannot know, which is everything the
/// AI repurposer measured about a clip that hasn't been posted yet.
class CoachVideoContext {
  final String transcript;
  final double? durationSeconds;
  final String hookLine;
  final String caption;
  final List<String> hashtags;
  final String verdict;
  final List<String> issues;
  final List<String> strengths;
  final int? footageScore;
  final double? wordsPerMinute;
  final double? silencePercent;

  const CoachVideoContext({
    this.transcript = '',
    this.durationSeconds,
    this.hookLine = '',
    this.caption = '',
    this.hashtags = const [],
    this.verdict = '',
    this.issues = const [],
    this.strengths = const [],
    this.footageScore,
    this.wordsPerMinute,
    this.silencePercent,
  });

  /// The backend caps the transcript field at 60k characters. A very long
  /// upload is trimmed here rather than rejected there, so a two-hour
  /// podcast still gets a coach that has read most of it.
  static const int _maxTranscriptChars = 60000;

  Map<String, dynamic> toJson() => {
        'transcript': transcript.length > _maxTranscriptChars
            ? transcript.substring(0, _maxTranscriptChars)
            : transcript,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
        'hook_line': hookLine,
        'caption': caption,
        'hashtags': hashtags,
        'verdict': verdict,
        'issues': issues,
        'strengths': strengths,
        if (footageScore != null) 'footage_score': footageScore,
        if (wordsPerMinute != null) 'words_per_minute': wordsPerMinute,
        if (silencePercent != null) 'silence_percent': silencePercent,
      };

  bool get isEmpty =>
      transcript.isEmpty &&
      hookLine.isEmpty &&
      caption.isEmpty &&
      verdict.isEmpty &&
      issues.isEmpty &&
      strengths.isEmpty &&
      footageScore == null;
}

/// One frame of a streaming Coach reply.
///
/// [delta] appends to the bubble, [replace] swaps its whole contents
/// (the backend sends that only when trimming moved the text out from
/// under what it already streamed), and [done] closes the turn and
/// carries the tappable follow-ups.
class CoachStreamEvent {
  final String? delta;
  final String? replace;
  final bool done;
  final List<String> suggestions;
  final String? error;
  final String? warning;

  const CoachStreamEvent({
    this.delta,
    this.replace,
    this.done = false,
    this.suggestions = const [],
    this.error,
    this.warning,
  });

  factory CoachStreamEvent.fromJson(Map<String, dynamic> json) =>
      CoachStreamEvent(
        delta: json['delta'] as String?,
        replace: json['replace'] as String?,
        done: json['done'] == true,
        suggestions: List<String>.from(json['suggestions'] ?? const []),
        error: json['error'] as String?,
        warning: json['warning'] as String?,
      );
}
