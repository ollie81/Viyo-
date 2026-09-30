
import 'package:flutter/material.dart';
import '../../widgets/create_menu_sheet.dart';
import '../../widgets/viyo_glass_bottom_nav.dart';
import '../dramas/drama_home_screen.dart';
import '../mission_screen.dart';
import '../post/create_post_screen.dart';
import '../post/upload_ai_drama_screen.dart';
import '../profile/profile_screen.dart';
import '../search_screen.dart';
import '../feed_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Missions dropped out of the tab bar (see ViyoGlassBottomNav) — the
  // "Create / Join Challenge" menu option below now pushes it as its
  // own screen instead of switching to a tab that no longer exists,
  // the same way "AI Short Drama" already worked.
  final _screens = const [
    FeedScreen(),
    SearchScreen(),
    CreatePostScreen(),
    ProfileScreen(),
    DramaHomeScreen(),
  ];

  // The "+" tab (index 2) is CreatePostScreen in the IndexedStack above
  // for the plain-upload choice, but never lands there directly — every
  // tap opens the create menu first, since "AI Short Drama" needs its
  // own pushed screen (a series + episode picker), not a fourth tab.
  Future<void> _handleNavTap(int index) async {
    if (index != 2) {
      setState(() => _index = index);
      return;
    }

    final choice = await showCreateMenuSheet(context);
    if (!mounted || choice == null) return;

    switch (choice) {
      case CreateMenuChoice.photoVideo:
        setState(() => _index = 2);
        break;
      case CreateMenuChoice.aiDrama:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UploadAiDramaScreen()),
        );
        break;
      case CreateMenuChoice.challenge:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MissionsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: ViyoGlassBottomNav(
        currentIndex: _index,
        onTap: _handleNavTap,
      ),
    );
  }
}
