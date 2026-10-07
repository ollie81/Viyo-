
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

  // Every one of these five screens fires its own network calls
  // (posts, series, profile data...) the moment it's built — an
  // IndexedStack with all five as children builds every single one
  // immediately at app start, regardless of which tab is actually
  // showing, which is what was turning app startup into a dozen-plus
  // parallel requests before the viewer had looked at four of the five
  // tabs. _visited tracks which tabs have actually been opened at
  // least once; build() below only instantiates a tab's real screen
  // once it's in this set, so the other four stay un-built (and fetch
  // nothing) until actually tapped. Once built, a screen stays in the
  // tree and keeps its state when switching away — same as a plain
  // IndexedStack — since _screens[i] is always the same widget
  // instance, just conditionally included.
  final Set<int> _visited = {0};

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
      setState(() { _index = index; _visited.add(index); });
      return;
    }

    final choice = await showCreateMenuSheet(context);
    if (!mounted || choice == null) return;

    switch (choice) {
      case CreateMenuChoice.photoVideo:
        setState(() { _index = 2; _visited.add(2); });
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
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < _screens.length; i++)
            _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: ViyoGlassBottomNav(
        currentIndex: _index,
        onTap: _handleNavTap,
      ),
    );
  }
}
