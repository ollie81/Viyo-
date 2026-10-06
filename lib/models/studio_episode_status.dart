/// Studio progress for one episode of a series — how far Phase 3/4
/// have gotten for it, used by the Studio home screen so the admin
/// can see where they left off instead of re-pasting a script.
class StudioEpisodeStatus {
  final int episodeNumber;
  final int sceneCount;
  final bool imagesDone;
  final bool audioDone;
  final bool published;
  final String? postId;

  const StudioEpisodeStatus({
    required this.episodeNumber,
    required this.sceneCount,
    required this.imagesDone,
    required this.audioDone,
    required this.published,
    this.postId,
  });

  factory StudioEpisodeStatus.fromJson(Map<String, dynamic> json) => StudioEpisodeStatus(
        episodeNumber: (json['episode_number'] as num).toInt(),
        sceneCount: (json['scene_count'] as num).toInt(),
        imagesDone: json['images_done'] ?? false,
        audioDone: json['audio_done'] ?? false,
        published: json['published'] ?? false,
        postId: json['post_id'] as String?,
      );
}
