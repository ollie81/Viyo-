import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_data.dart';

class StorageService {
  static const String _key = 'viyo_user_data';

  static List<Mission> get defaultMissions => [
        Mission(
          id: 'login',
          title: 'Daily Check-in',
          description: 'Open the app today',
          coins: 50,
          type: 'daily',
        ),
        Mission(
          id: 'post',
          title: 'Share Content',
          description: 'Post or share a link to your latest content',
          coins: 100,
          type: 'daily',
        ),
        Mission(
          id: 'inspire',
          title: 'Read Inspiration',
          description: 'Read today\'s inspiration feed',
          coins: 30,
          type: 'daily',
        ),
        Mission(
          id: 'profile',
          title: 'Complete Profile',
          description: 'Add your name and creator niche',
          coins: 80,
          type: 'one-time',
        ),
        Mission(
          id: 'refer',
          title: 'Invite a Friend',
          description: 'Share Viyo with another creator',
          coins: 200,
          type: 'referral',
        ),
      ];

  static List<Badge> get defaultBadges => [
        Badge(
          id: 'starter',
          name: 'Viyo Pioneer',
          description: 'Joined the creator boost movement',
          cost: 0,
          unlocked: true,
        ),
        Badge(
          id: 'streak3',
          name: '3-Day Streak',
          description: 'Logged in 3 days in a row',
          cost: 150,
        ),
        Badge(
          id: 'streak7',
          name: 'Week Warrior',
          description: '7-day login streak',
          cost: 400,
        ),
        Badge(
          id: 'earner',
          name: 'Coin Collector',
          description: 'Earned 1,000 total coins',
          cost: 300,
        ),
        Badge(
          id: 'gifter',
          name: 'Generous Creator',
          description: 'Gifted coins to 3 friends',
          cost: 250,
        ),
        Badge(
          id: 'boost',
          name: 'Visibility Boost',
          description: 'Temporary profile highlight (7 days)',
          cost: 500,
        ),
      ];

  static UserData getDefaultUser([String name = 'Creator']) {
    return UserData(
      name: name,
      missions: defaultMissions.map((m) => Mission(
            id: m.id,
            title: m.title,
            description: m.description,
            coins: m.coins,
            type: m.type,
          )).toList(),
      transactions: [],
      badges: defaultBadges.map((b) => Badge(
            id: b.id,
            name: b.name,
            description: b.description,
            cost: b.cost,
            unlocked: b.unlocked,
          )).toList(),
    );
  }

  static Future<UserData> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return getDefaultUser();
    try {
      return UserData.fromJson(jsonDecode(raw));
    } catch (_) {
      return getDefaultUser();
    }
  }

  static Future<void> saveUser(UserData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));
  }

  static Future<void> resetUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}