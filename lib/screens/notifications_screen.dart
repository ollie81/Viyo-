import 'package:flutter/material.dart';
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
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _notifications.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(
                            child: Text('No notifications yet', style: TextStyle(color: AppColors.textMuted)),
                          ),
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
