enum EngagementType { follow, like, comment }

/// One real engagement event on the creator's own content — a follow, a
/// like, or a comment — used to build the "Who's Engaging With You"
/// digest. occurredAt is nullable because likes/follows aren't
/// guaranteed to carry a created_at the client can safely order by;
/// when it's missing the event still shows, just without a specific time.
class EngagementEvent {
  final EngagementType type;
  final String actorId;
  final String actorUsername;
  final String actorDisplayName;
  final String? actorAvatarUrl;
  final DateTime? occurredAt;
  final String? postCaption;

  EngagementEvent({
    required this.type,
    required this.actorId,
    required this.actorUsername,
    required this.actorDisplayName,
    this.actorAvatarUrl,
    this.occurredAt,
    this.postCaption,
  });
}
