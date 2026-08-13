import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/post.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/post_card.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;
  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  final _commentCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final comments = await PostService.getComments(widget.post.id);
    if (!mounted) return;
    setState(() {
      _comments = comments;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final userId = SupabaseService.currentUserId;
    final content = _commentCtrl.text.trim();
    if (userId == null || content.isEmpty) return;

    setState(() => _sending = true);
    try {
      await PostService.addComment(postId: widget.post.id, userId: userId, content: content);
      _commentCtrl.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _like() async {
    try {
      await PostService.toggleLike(widget.post);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update like: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Post')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                PostCard(post: widget.post, onLike: _like, onComment: () {}, enableMediaTap: false),
                const SizedBox(height: 10),
                const Text('Comments', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: AppColors.primary))
                else if (_comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Be the first to comment', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  ..._comments.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.surfaceBorder,
                              child: Text((c['profiles']?['display_name'] ?? '?')[0].toUpperCase(),
                                  style: const TextStyle(fontSize: 11)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['profiles']?['display_name'] ?? 'Unknown',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text(c['content'], style: const TextStyle(fontSize: 13)),
                                  Text(
                                    timeago.format(DateTime.parse(c['created_at'])),
                                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(hintText: 'Add a comment...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _sending
                        ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.send, color: AppColors.primary),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
