import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../screens/messages/chat_screen.dart';
import '../screens/notifications_screen.dart';
import 'supabase_service.dart';

/// Push notifications via Firebase Cloud Messaging. Registers this
/// device's token against the signed-in user (see viyo_ai's push.py,
/// which reads it back to actually send a push), and routes a tapped
/// notification to the in-app Notifications screen.
///
/// Every step here is wrapped so a missing/misconfigured Firebase
/// project (no google-services.json dropped in yet — see
/// android/app/build.gradle.kts) degrades to "push notifications
/// don't work" rather than crashing the app at startup.
class PushNotificationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static bool _initialized = false;

  static Future<void> init(String userId) async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // No Firebase config present yet — push notifications simply
      // won't work until google-services.json is added.
      return;
    }
    _initialized = true;

    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}

    await _registerToken(userId);
    FirebaseMessaging.instance.onTokenRefresh.listen((token) => _saveToken(userId, token));

    // App opened by tapping a notification while backgrounded, or a
    // cold start from a terminated state via a tapped notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) _handleTap(initialMessage);

    // Foreground messages intentionally show nothing extra right now —
    // Android doesn't surface a system-tray banner for a foreground
    // FCM message on its own (that needs flutter_local_notifications),
    // and push's main value is bringing someone back when the app
    // isn't already open in front of them.
  }

  static Future<void> _registerToken(String userId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(userId, token);
    } catch (_) {}
  }

  static Future<void> _saveToken(String userId, String token) async {
    try {
      await SupabaseService.client.from('device_tokens').upsert(
        {'user_id': userId, 'token': token, 'platform': 'android'},
        onConflict: 'token',
      );
    } catch (_) {
      // Best-effort — a failed token save just means this device
      // won't receive pushes until the next successful registration.
    }
  }

  /// Removes this device's token so a signed-out user stops receiving
  /// pushes meant for whoever signs in next on the same device.
  static Future<void> unregister() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await SupabaseService.client.from('device_tokens').delete().eq('token', token);
      }
    } catch (_) {}
  }

  static void _openNotifications() {
    navigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
  }

  /// A tapped message notification goes straight to the conversation
  /// rather than the generic notifications list — every other
  /// notification type still lands there, since there's no dedicated
  /// screen per like/comment/follow to jump to instead.
  static void _handleTap(RemoteMessage message) {
    final data = message.data;
    if (data['type'] == 'message' &&
        data['conversation_id'] != null &&
        data['sender_id'] != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: data['conversation_id'] as String,
            otherUserId: data['sender_id'] as String,
            // The real name isn't in the push payload — the chat
            // screen only needs it for the app bar label, and it
            // corrects itself the moment the conversation list is
            // next opened. Better than blocking navigation on a
            // profile fetch before the chat can even open.
            otherName: message.notification?.title?.replaceFirst('New message from ', '') ?? 'Message',
          ),
        ),
      );
      return;
    }
    _openNotifications();
  }
}
