import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/engagement_event.dart';
import '../services/engagement_service.dart';
import '../theme/app_theme.dart';

/// "Who's Engaging With You" — a small digest of real, recent activity
/// on the creator's own posts (new followers, comments, likes). The same
/// curiosity/ego pull that makes people check Instagram notifications,
/// grounded entirely in Viyo's own data — nothing here is invented.
class EngagementDigestCard extends StatefulWidget {
  final String userId;
  const EngagementDigestCard({super.key, required this.userId});

  @override
  State<EngagementDigestCard> createState() => _EngagementDigestCardState();
}

class _EngagementDigestCardState extends State<EngagementDigestCard> {
  List<EngagementEvent>? _events;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await EngagementService.getRecentActivity(widget.userId);
      if (mounted) setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _events = const []);
    }
  }

  String _verb(EngagementEvent e) {
    switch (e.type) {
      case EngagementType.follow:
        return 'started following you';
      case EngagementType.like:
        return 'liked your post';
      case EngagementType.comment:
        return 'commented on your post';
    }
  }

  IconData _icon(EngagementType t) {
    switch (t) {
      case EngagementType.follow:
        return Icons.person_add_alt_1;
      case EngagementType.like:
        return Icons.favorite;
      case EngagementType.comment:
        return Icons.mode_comment;
    }
  }

  Color _iconColor(EngagementType t) {
    switch (t) {
      case EngagementType.follow:
        return AppColors.primary;
      case EngagementType.like:
        return AppColors.secondary;
      case EngagementType.comment:
        return AppColors.coin;
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.groups_2_outlined, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text("Who's Engaging With You", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          if (events == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else if (events.isEmpty)
            const Text(
              'No activity yet — share a post and this fills up as people find it.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            )
          else
            for (final e in events.take(5)) _row(e),
        ],
      ),
    );
  }

  Widget _row(EngagementEvent e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.surfaceBorder,
            backgroundImage: e.actorAvatarUrl != null ? NetworkImage(e.actorAvatarUrl!) : null,
            child: e.actorAvatarUrl == null
                ? Text(
                    e.actorDisplayName.isNotEmpty ? e.actorDisplayName[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 11),
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                children: [
                  TextSpan(text: e.actorDisplayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' ${_verb(e)}'),
                  if (e.occurredAt != null)
                    TextSpan(
                      text: '  ·  ${timeago.format(e.occurredAt!, allowFromNow: true)}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          Icon(_icon(e.type), size: 15, color: _iconColor(e.type)),
        ],
      ),
    );
  }
}
