import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import '../../services/post_service.dart';    
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coin_badge.dart';
import '../settings_screen.dart';
import '../store_screen.dart';
import '../wallet_screen.dart';
import '../post/post_detail_screen.dart';
import 'edit_profile.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // null = current user's own profile
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserProfile? _profile;
  List<Post> _posts = [];
  int _followers = 0;
  int _following = 0;
  bool _isFollowing = false;
  bool _loading = true;

  bool get _isOwnProfile =>
      widget.userId == null || widget.userId == SupabaseService.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final targetId = widget.userId ?? SupabaseService.currentUserId;
    if (targetId == null) return;
    setState(() => _loading = true);

    final profile = await ProfileService.getProfile(targetId);
    final posts = _isOwnProfile
        ? await PostService.getUserPosts(targetId)
        : await PostService.getPublicUserPosts(targetId);
    final followers = await ProfileService.getFollowerCount(targetId);
    final following = await ProfileService.getFollowingCount(targetId);

    bool isFollowing = false;
    final myId = SupabaseService.currentUserId;
    if (!_isOwnProfile && myId != null) {
      isFollowing = await ProfileService.isFollowing(myId, targetId);
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _posts = posts;
      _followers = followers;
      _following = following;
      _isFollowing = isFollowing;
      _loading = false;
    });
  }

  Future<void> _toggleFollow() async {
    final myId = SupabaseService.currentUserId;
    final targetId = widget.userId;
    if (myId == null || targetId == null) return;

    if (_isFollowing) {
      await ProfileService.unfollow(myId, targetId);
    } else {
      await ProfileService.follow(myId, targetId);
    }
    _load();
  }

  Future<void> _shareProfile() async {
    if (_profile == null) return;
    await Share.share(
      "I'm boosting my creator journey on Viyo 🔥 Follow @${_profile!.username} — join free with code ${_profile!.referralCode}!",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final p = _profile!;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('@${p.username}'),
        actions: _isOwnProfile
            ? [
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                ),
              ]
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: AppColors.surfaceBorder,
                  backgroundImage: p.avatarUrl != null ? NetworkImage(p.avatarUrl!) : null,
                  child: p.avatarUrl == null
                      ? Text(p.displayName.isNotEmpty ? p.displayName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 28))
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.displayName,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          if (p.isPremium) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.verified, color: AppColors.secondary, size: 18),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _statChip('$_followers', 'Followers'),
                          const SizedBox(width: 16),
                          _statChip('$_following', 'Following'),
                          const SizedBox(width: 16),
                          _statChip('${_posts.length}', 'Posts'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (p.bio.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(p.bio, style: const TextStyle(color: Colors.white70)),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.card(),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Rank', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      Text('${p.rank} · Lvl ${p.level}',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Streak', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                      Text('${p.currentStreak} days 🔥', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (_isOwnProfile)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'Balance',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        CoinBadge(amount: p.pointsBalance),
                      ],
                    )
                  else
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Creator',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          'Profile',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isOwnProfile)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: p)),
                      ).then((_) => _load()),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const WalletScreen()),
                      ),
                      child: const Text('Wallet'),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _toggleFollow,
                      style: _isFollowing
                          ? ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              foregroundColor: Colors.white70,
                            )
                          : null,
                      child: Text(_isFollowing ? 'Following' : 'Follow'),
                    ),
                  ),
                ],
              ),
            if (_isOwnProfile) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const StoreScreen()),
                      ),
                      child: const Text('Store'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _shareProfile,
                      child: const Text('Share Profile ↗'),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const Text('Posts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            if (_posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text('No posts yet', style: TextStyle(color: AppColors.textMuted)),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _posts.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemBuilder: (ctx, i) {
                  final post = _posts[i];
                  return GestureDetector(
                    // Tap opens the post detail (works for everyone).
                    onTap: () => Navigator.of(ctx).push(
                      MaterialPageRoute(
                        builder: (_) => PostDetailScreen(post: post),
                      ),
                    ),
                    // Long-press shows owner-only management menu.
                    onLongPress: _isOwnProfile ? () => _showPostMenu(post) : null,
                    child: Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            image: post.mediaUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(post.thumbnailUrl ?? post.mediaUrl!),
                                    fit: BoxFit.cover,
                                    colorFilter: post.isArchived
                                        ? ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken)
                                        : null,
                                  )
                                : null,
                          ),
                          child: post.mediaUrl == null
                              ? Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Text(
                                    post.caption,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                                  ),
                                )
                              : null,
                        ),
                        if (post.postType == PostType.video)
                          const Positioned(
                            right: 4,
                            bottom: 4,
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 22,
                              color: Colors.white,
                            ),
                          ),
                        if (post.isPinned)
                          const Positioned(
                            top: 4,
                            left: 4,
                            child: Icon(Icons.push_pin, size: 14, color: Colors.white),
                          ),
                        if (post.isPrivate)
                          const Positioned(
                            top: 4,
                            right: 4,
                            child: Icon(Icons.lock, size: 14, color: Colors.white),
                          ),
                        if (post.isBoosted)
                          const Positioned(
                            bottom: 4,
                            left: 4,
                            child: Icon(Icons.trending_up, size: 14, color: AppColors.secondary),
                          ),
                        if (post.isArchived)
                          const Positioned(
                            bottom: 4,
                            right: 4,
                            child: Icon(Icons.archive_outlined, size: 14, color: Colors.white70),
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPostMenu(Post post) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(post.isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(post.isPinned ? 'Unpin from profile' : 'Pin to top of profile'),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: Icon(post.isPrivate ? Icons.lock_open : Icons.lock_outline),
              title: Text(post.isPrivate ? 'Make public' : 'Make private'),
              onTap: () => Navigator.pop(ctx, 'private'),
            ),
            ListTile(
              leading: Icon(post.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(post.isArchived ? 'Unarchive' : 'Archive (hide without deleting)'),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
            ListTile(
              leading: const Icon(Icons.trending_up, color: AppColors.secondary),
              title: const Text('Boost this post (50 coins)'),
              onTap: () => Navigator.pop(ctx, 'boost'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('Delete post', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;

    try {
      switch (action) {
        case 'pin':
          await PostService.setPinned(post.id, !post.isPinned);
          break;
        case 'private':
          await PostService.setPrivate(post.id, !post.isPrivate);
          break;
        case 'archive':
          await PostService.setArchived(post.id, !post.isArchived);
          break;
        case 'boost':
          final userId = SupabaseService.currentUserId;
          if (userId == null) return;
          await PostService.boostPost(userId: userId, postId: post.id, cost: 50);
          break;
        case 'delete':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Delete post?'),
              content: const Text("This can't be undone."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
              ],
            ),
          );
          if (confirmed != true) return;
          await PostService.deletePost(post);
          break;
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  Widget _statChip(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      ],
    );
  }
}
