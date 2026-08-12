import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ViyoGlassBottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const ViyoGlassBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Discover'),
    (Icons.add_rounded, Icons.add_rounded, 'Post'),
    (Icons.flag_outlined, Icons.flag_rounded, 'Missions'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            height: 66,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(.36),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withOpacity(.10)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.28),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: List.generate(_items.length, (i) {
                final item = _items[i];
                final active = currentIndex == i;
                final isPost = i == 2;
                return Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: isPost ? 48 : 62,
                        height: isPost ? 48 : 52,
                        decoration: BoxDecoration(
                          color: isPost
                              ? AppColors.primary
                              : active
                                  ? Colors.white.withOpacity(.11)
                                  : Colors.transparent,
                          borderRadius: BorderRadius.circular(isPost ? 17 : 18),
                          boxShadow: isPost
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(.32),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              active ? item.$2 : item.$1,
                              size: isPost ? 28 : 22,
                              color: isPost
                                  ? Colors.white
                                  : active
                                      ? Colors.white
                                      : Colors.white.withOpacity(.58),
                            ),
                            if (!isPost) ...[
                              const SizedBox(height: 2),
                              Text(
                                item.$3,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: active
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: active
                                      ? Colors.white
                                      : Colors.white.withOpacity(.58),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
