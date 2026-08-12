import 'package:cached_network_image/cached_network_image.dart';
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
import 'edit_profile.dart';
import '../post/viyo_post_viewer.dart';
import '../post/post_detail_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;
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
  int _tab = 0;

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
    if (mounted) setState(() => _loading = true);

    final profile = await ProfileService.getProfile(targetId);
    final posts = _isOwnProfile
        ? await PostService.getUserPosts(targetId)
        : await PostService.getPublicUserPosts(targetId);
    final followers = await ProfileService.getFollowerCount(targetId);
    final following = await ProfileService.getFollowingCount(targetId);

    var followingMe = false;
    final myId = SupabaseService.currentUserId;
    if (!_isOwnProfile && myId != null) {
      followingMe = await ProfileService.isFollowing(myId, targetId);
    }

    if (!mounted) return;
    setState(() {
      _profile = profile;
      _posts = posts;
      _followers = followers;
      _following = following;
      _isFollowing = followingMe;
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
    await _load();
  }

  Future<void> _shareProfile() async {
    final p = _profile;
    if (p == null) return;
    await Share.share(
      "Check out @${p.username} on Viyo — ${p.bio.isEmpty ? 'creator profile' : p.bio}",
    );
  }

  List<Post> get _visiblePosts {
    if (_tab == 1) return _posts.where((p) => p.postType == PostType.video).toList();
    if (_tab == 2) return _posts.where((p) => p.postType == PostType.photo).toList();
    return _posts;
  }

  Future<void> _openCreatorContent(Post selected) async {
    final index = _posts.indexWhere((p) => p.id == selected.id);
    if (index < 0) return;

    final media = _posts
        .where((p) => p.postType == PostType.photo || p.postType == PostType.video)
        .map((p) => ViyoPostMedia.fromPost(p))
        .toList();
    final mediaIndex = media.indexWhere((m) => m.id == selected.id);
    if (mediaIndex < 0) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ViyoPostViewer(
          posts: media,
          initialIndex: mediaIndex,
          onLike: () => _likePost(selected),
          onComment: () => _commentPost(selected),
          onShare: () => _sharePost(selected),
        ),
      ),
    );
  }

  Future<void> _likePost(Post post) async {
    try {
      await PostService.toggleLike(post);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    }
  }

  Future<void> _commentPost(Post post) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
    if (mounted) await _load();
  }

  Future<void> _sharePost(Post post) async {
    await Share.share(
      post.mediaUrl ?? post.caption,
      subject: 'Viyo post by ${post.authorUsername ?? 'creator'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _profile == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final p = _profile!;
    final posts = _visiblePosts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text(
          '@${p.username}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isOwnProfile)
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.ios_share_outlined),
              onPressed: _shareProfile,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Hero(
                          tag: 'profile-avatar-${p.id}',
                          child: CircleAvatar(
                            radius: 46,
                            backgroundColor: AppColors.surfaceBorder,
                            backgroundImage: p.avatarUrl == null
                                ? null
                                : CachedNetworkImageProvider(p.avatarUrl!),
                            child: p.avatarUrl == null
                                ? Text(
                                    p.displayName.isNotEmpty
                                        ? p.displayName[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _stat('${_posts.length}', 'Posts'),
                              _stat('$_followers', 'Followers'),
                              _stat('$_following', 'Following'),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              p.displayName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          if (p.isPremium) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              color: AppColors.secondary,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '@${p.username}',
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (p.bio.trim().isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          p.bio,
                          style: const TextStyle(
                            color: Colors.white70,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _isOwnProfile
                              ? OutlinedButton(
                                  onPressed: () => Navigator.of(context)
                                      .push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EditProfileScreen(profile: p),
                                    ),
                                  )
                                      .then((_) => _load()),
                                  child: const Text('Edit profile'),
                                )
                              : ElevatedButton(
                                  onPressed: _toggleFollow,
                                  style: _isFollowing
                                      ? ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.surface,
                                          foregroundColor: Colors.white,
                                        )
                                      : null,
                                  child: Text(
                                    _isFollowing ? 'Following' : 'Follow',
                                  ),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _shareProfile,
                            child: const Text('Share'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: AppTheme.card(),
                      child: Row(
                        children: [
                          const Icon(Icons.local_fire_department_outlined),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Rank ${p.rank}  ·  Level ${p.level}  ·  ${p.currentStreak} day streak',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_isOwnProfile)
                            CoinBadge(amount: p.pointsBalance),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _tabButton(0, Icons.grid_on_rounded, 'Posts'),
                        _tabButton(1, Icons.play_circle_outline, 'Videos'),
                        _tabButton(2, Icons.photo_outlined, 'Photos'),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            if (posts.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text(
                      'No posts yet',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _mediaTile(posts[i]),
                    childCount: posts.length,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                    childAspectRatio: 0.78,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _stat(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _tabButton(int index, IconData icon, String label) {
    final active = _tab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: active ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? Colors.white : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 2,
                width: active ? 32 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mediaTile(Post post) {
    final isVideo = post.postType == PostType.video;
    final isText = post.mediaUrl == null;

    return GestureDetector(
      onTap: () => isText ? _commentPost(post) : _openCreatorContent(post),
      onDoubleTap: () => _likePost(post),
      onLongPress: _isOwnProfile ? () => _showPostMenu(post) : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!isText)
              CachedNetworkImage(
                imageUrl: post.thumbnailUrl ?? post.mediaUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) =>
                    Container(color: AppColors.surfaceBorder),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.surfaceBorder,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: AppColors.textMuted,
                  ),
                ),
              )
            else
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.all(10),
                child: Text(
                  post.caption,
                  maxLines: 7,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ),
            if (isVideo)
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        size: 14,
                        color: Colors.white,
                      ),
                      if (post.durationSeconds != null)
                        Text(
                          _fmtDuration(post.durationSeconds!),
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (post.postType == PostType.photo)
              const Positioned(
                right: 7,
                bottom: 7,
                child: Icon(
                  Icons.photo_outlined,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            Positioned(
              top: 7,
              right: 7,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _sharePost(post),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.ios_share_outlined, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
            if (post.isPinned)
              const Positioned(
                left: 7,
                top: 7,
                child: Icon(Icons.push_pin, size: 15, color: Colors.white),
              ),
            if (post.isBoosted)
              const Positioned(
                left: 7,
                bottom: 7,
                child: Icon(
                  Icons.trending_up,
                  size: 15,
                  color: AppColors.secondary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showTextPost(Post post) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Text(
          post.caption,
          style: const TextStyle(fontSize: 17, height: 1.45),
        ),
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
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
              leading: Icon(
                post.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                post.isPinned ? 'Unpin from profile' : 'Pin to top of profile',
              ),
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            ListTile(
              leading: Icon(
                post.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              title: Text(
                post.isArchived ? 'Unarchive' : 'Archive',
              ),
              onTap: () => Navigator.pop(ctx, 'archive'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: AppColors.danger,
              ),
              title: const Text(
                'Delete post',
                style: TextStyle(color: AppColors.danger),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == null) return;
    try {
      if (action == 'pin') {
        await PostService.setPinned(post.id, !post.isPinned);
      } else if (action == 'archive') {
        await PostService.setArchived(post.id, !post.isArchived);
      } else if (action == 'delete') {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete post?'),
            content: const Text("This can't be undone."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await PostService.deletePost(post);
        }
      }
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }
}
