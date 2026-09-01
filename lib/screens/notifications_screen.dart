import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;
    setState(() => _loading = true);
    final data = await NotificationService.getNotifications(userId);
    if (!mounted) return;
    setState(() {
      _notifications = data;
      _loading = false;
    });
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'like':
        return Icons.favorite;
      case 'comment':
        return Icons.mode_comment;
      case 'follow':
        return Icons.person_add;
      case 'gift':
        return Icons.card_giftcard;
      case 'mission':
        return Icons.flag;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Notifications')),
      body: _loading
          ? const _NotificationsSkeleton()
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _notifications.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(child: _EmptyNotificationsState()),
                        ),
                      ],
                    )
                  : ListView.builder(
                      itemCount: _notifications.length,
                      itemBuilder: (ctx, i) {
                        final n = _notifications[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: n['is_read'] == true
                                ? AppColors.surfaceBorder
                                : AppColors.primary.withOpacity(0.25),
                            child: Icon(_iconFor(n['type']), size: 18, color: AppColors.primary),
                          ),
                          title: Text(n['message'] ?? '', style: const TextStyle(fontSize: 14)),
                          subtitle: Text(
                            timeago.format(DateTime.parse(n['created_at'])),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                          onTap: () => NotificationService.markRead(n['id']),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Shown while notifications are loading — mimics a few notification rows
/// instead of a bare spinner.
class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.surfaceBorder,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 6,
        itemBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const CircleAvatar(radius: 20, backgroundColor: Colors.white),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(height: 12, width: 200, color: Colors.white),
                    const SizedBox(height: 6),
                    Container(height: 10, width: 80, color: Colors.white),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty-notifications state — icon-led, matching the feed/profile pattern.
class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.textMuted.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_none_rounded, color: AppColors.textMuted, size: 26),
        ),
        const SizedBox(height: 14),
        const Text('No notifications yet', style: TextStyle(color: AppColors.textMuted)),
      ],
    );
  }
}
