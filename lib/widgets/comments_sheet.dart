import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/post.dart';
import '../services/post_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'guest_gate.dart';
import 'spoiler_text.dart';

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
  bool _spoilerComposing = false;
  // The comment being replied to, if any — a top-level comment only
  // (replies are one level deep, no reply-to-a-reply, same as most
  // short-form comment sections).
  Map<String, dynamic>? _replyingTo;

  bool get _isPostOwner =>
      SupabaseService.currentUserId != null && SupabaseService.currentUserId == widget.post.userId;

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
      await PostService.addComment(
        postId: widget.post.id,
        userId: userId,
        content: content,
        parentId: _replyingTo?['id'] as String?,
        isSpoiler: _spoilerComposing,
      );
      _commentCtrl.clear();
      setState(() {
        _replyingTo = null;
        _spoilerComposing = false;
      });
      widget.onCommentAdded?.call();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not post comment: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _togglePin(Map<String, dynamic> comment) async {
    final pinned = comment['is_pinned'] == true;
    try {
      await PostService.pinComment(widget.post.id, comment['id'] as String, !pinned);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  // Top-level comments, pinned first (stable otherwise — the fetch is
  // already created_at-ascending, so this only reorders the pinned
  // ones to the front rather than fully re-sorting).
  List<Map<String, dynamic>> get _topLevel {
    final top = _comments.where((c) => c['parent_id'] == null).toList();
    top.sort((a, b) {
      final aPinned = a['is_pinned'] == true;
      final bPinned = b['is_pinned'] == true;
      if (aPinned == bPinned) return 0;
      return aPinned ? -1 : 1;
    });
    return top;
  }

  List<Map<String, dynamic>> _repliesTo(String parentId) =>
      _comments.where((c) => c['parent_id'] == parentId).toList();

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
                          itemCount: _topLevel.length,
                          itemBuilder: (_, i) {
                            final c = _topLevel[i];
                            final replies = _repliesTo(c['id'] as String);
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _commentTile(c, isReply: false),
                                  for (final r in replies)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 34, top: 10),
                                      child: _commentTile(r, isReply: true),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Replying to ${_replyingTo!['profiles']?['display_name'] ?? 'comment'}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = null),
                      child: const Icon(Icons.close, size: 16, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _spoilerComposing = !_spoilerComposing),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _spoilerComposing ? AppColors.secondary.withOpacity(0.18) : AppColors.surface,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _spoilerComposing ? AppColors.secondary : AppColors.surfaceBorder,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.visibility_off_outlined,
                              size: 12,
                              color: _spoilerComposing ? AppColors.secondary : AppColors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Spoiler',
                              style: TextStyle(
                                fontSize: 11,
                                color: _spoilerComposing ? AppColors.secondary : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentCtrl,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: _replyingTo != null ? 'Write a reply...' : 'Add a comment...',
                            ),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _commentTile(Map<String, dynamic> c, {required bool isReply}) {
    final pinned = c['is_pinned'] == true;
    final content = (c['content'] as String?) ?? '';
    // A real is_spoiler flag renders through the same SpoilerText a
    // literal ||text|| convention (Phase 1, still supported) already
    // uses — wrap the whole thing only if the author didn't already
    // mark part of it themselves.
    final isSpoilerFlag = c['is_spoiler'] == true;
    final displayText = isSpoilerFlag && !content.contains('||') ? '||$content||' : content;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 12 : 14,
          backgroundColor: AppColors.surfaceBorder,
          child: Text(
            (c['profiles']?['display_name'] ?? '?')[0].toUpperCase(),
            style: TextStyle(fontSize: isReply ? 10 : 11),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(c['profiles']?['display_name'] ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  if (pinned) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'PINNED',
                        style: TextStyle(fontSize: 8.5, color: AppColors.secondary, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ],
              ),
              SpoilerText(text: displayText, style: const TextStyle(fontSize: 13)),
              Row(
                children: [
                  Text(
                    timeago.format(DateTime.tryParse(c['created_at'] as String? ?? '') ?? DateTime.now()),
                    style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                  ),
                  if (!isReply) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = c),
                      child: const Text('Reply',
                          style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (_isPostOwner) ...[
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: () => _togglePin(c),
                      child: Text(
                        pinned ? 'Unpin' : 'Pin',
                        style: const TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
