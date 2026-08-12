    
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/viyo_glass_bottom_nav.dart';
import '../mission_screen.dart';
import '../post/create_post_screen.dart';
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
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: ViyoGlassBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}
