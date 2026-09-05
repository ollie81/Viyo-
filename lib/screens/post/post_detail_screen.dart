import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/insufficient_coins_exception.dart';
import '../../models/post.dart';
import '../../models/post_insight.dart';
import '../../services/ai_service.dart';
import '../../services/post_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/guest_gate.dart';
import '../../widgets/insufficient_coins_sheet.dart';
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

  PostInsight? _insight;
  bool _loadingInsight = false;
  String? _insightError;

  bool get _isOwnPost => widget.post.userId == SupabaseService.currentUserId;

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
    if (!await GuestGate.allow(context, action: 'comment')) return;

    setState(() => _sending = true);
    try {
      await PostService.addComment(postId: widget.post.id, userId: userId, content: content);
      _commentCtrl.clear();
      await _load();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loadInsight() async {
    setState(() {
      _loadingInsight = true;
      _insightError = null;
    });
    try {
      final insight = await AiService.getPostInsight(widget.post.id);
      if (mounted) setState(() => _insight = insight);
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      if (mounted) setState(() => _insightError = 'Could not load insight: $e');
    } finally {
      if (mounted) setState(() => _loadingInsight = false);
    }
  }

  Color _performanceColor(String? performance) {
    switch (performance) {
      case 'above':
        return AppColors.success;
      case 'below':
        return AppColors.danger;
      default:
        return AppColors.coin;
    }
  }

  String _performanceLabel(String? performance) {
    switch (performance) {
      case 'above':
        return 'ABOVE YOUR AVERAGE';
      case 'below':
        return 'BELOW YOUR AVERAGE';
      case 'about':
        return 'ABOUT YOUR AVERAGE';
      default:
        return 'FIRST FEW POSTS';
    }
  }

  Widget _whyThisWorkedSection() {
    if (!_isOwnPost) return const SizedBox.shrink();

    if (_insight != null) {
      final insight = _insight!;
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(borderColor: _performanceColor(insight.performance).withOpacity(0.4)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights, size: 15, color: _performanceColor(insight.performance)),
                const SizedBox(width: 6),
                const Text('Why This Worked', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _performanceColor(insight.performance).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _performanceLabel(insight.performance),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: _performanceColor(insight.performance),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(insight.explanation, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _loadingInsight ? null : _loadInsight,
            icon: _loadingInsight
                ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.insights, size: 16),
            label: _loadingInsight
                ? const Text('Analyzing...')
                : const _CoinButtonLabel(text: 'Why This Worked', cost: FeatureCoinCosts.postInsight),
          ),
          if (_insightError != null) ...[
            const SizedBox(height: 6),
            Text(_insightError!, style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Future<void> _like() async {
    if (!await GuestGate.allow(context, action: 'like posts')) return;
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
                _whyThisWorkedSection(),
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

/// A button label with a small coin-cost chip — matches the chip used
/// on the AI buttons in create_post_screen.dart.
class _CoinButtonLabel extends StatelessWidget {
  final String text;
  final int cost;
  const _CoinButtonLabel({required this.text, required this.cost});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.coin.withOpacity(0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.monetization_on, size: 11, color: AppColors.coin),
              const SizedBox(width: 2),
              Text('$cost', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.coin)),
            ],
          ),
        ),
      ],
    );
  }
}
