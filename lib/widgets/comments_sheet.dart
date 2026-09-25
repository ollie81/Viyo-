import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'guest_gate.dart';

/// Comments as a partial-height overlay instead of a full navigation.
///
/// Extracted specifically for the video feed: pushing a whole new
/// screen for comments left an autoplaying VideoPlayerController
/// mounted (and still playing) underneath the new route — the
/// PageView never changed pages, so nothing ever told that page it
/// was no longer active. The creator would tap "comment" and the
/// video would vanish behind an opaque screen while its audio kept
/// running, which is exactly what a modal bottom sheet fixes on its
/// own: it's a translucent overlay, so the video underneath keeps
/// painting (and keeps playing) in whatever's left visible, the same
/// way Instagram/TikTok's comment sheets work.
Future<void> showCommentsSheet(BuildContext context, Post post, {VoidCallback? onCommentAdded}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _CommentsSheet(post: post, onCommentAdded: onCommentAdded),
  );
}

class _CommentsSheet extends StatefulWidget {
  final Post post;
  // Fired right after a comment is actually saved — not returned as the
  // sheet's pop result, since swiping the sheet away dismisses it with
  // no result at all. Lets the screen underneath (still visible through
  // the translucent overlay) bump its own comment count live instead of
  // only catching up the next time it happens to reload from scratch.
  final VoidCallback? onCommentAdded;
  const _CommentsSheet({required this.post, this.onCommentAdded});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _commentCtrl = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
    if (!await GuestGate.allow(context, action: 'comment')) return;

    setState(() => _sending = true);
    try {
      await PostService.addComment(postId: widget.post.id, userId: userId, content: content);
      _commentCtrl.clear();
      widget.onCommentAdded?.call();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Comments', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const Divider(height: 1, color: AppColors.surfaceBorder),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _comments.isEmpty
                      ? const Center(
                          child: Text('Be the first to comment', style: TextStyle(color: AppColors.textMuted)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _comments.length,
                          itemBuilder: (_, i) {
                            final c = _comments[i];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppColors.surfaceBorder,
                                    child: Text(
                                      (c['profiles']?['display_name'] ?? '?')[0].toUpperCase(),
                                      style: const TextStyle(fontSize: 11),
                                    ),
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
                            );
                          },
                        ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(hintText: 'Add a comment...'),
                        onSubmitted: (_) => _send(),
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
      ),
    );
  }
}
