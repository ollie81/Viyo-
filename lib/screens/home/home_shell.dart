import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../missions_screen.dart';
import '../post/create_post_screen.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import 'feed_screen.dart';

/// Bottom-nav container for the 5 primary tabs. Notifications, wallet,
/// store, settings, and invite-friends are reached from the Profile tab
/// or app bar actions rather than the bottom nav, to keep the nav bar
/// uncluttered (5 items max).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _screens = const [
    FeedScreen(),
    SearchScreen(),
    CreatePostScreen(),
    MissionsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Discover'),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle, color: AppColors.primary, size: 32),
            label: 'Post',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.flag_outlined), label: 'Missions'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}
