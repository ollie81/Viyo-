import 'package:flutter/material.dart';
import '../../models/insufficient_coins_exception.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/insufficient_coins_sheet.dart';

/// Persistent Coach conversation attached to one specific video.
/// The backend stores the history in Supabase, so leaving the screen
/// and reopening the same video does not erase the conversation.
class VideoCoachScreen extends StatefulWidget {
  final String videoId;

  const VideoCoachScreen({
    super.key,
    required this.videoId,
  });

  @override
  State<VideoCoachScreen> createState() => _VideoCoachScreenState();
}

class _VideoCoachScreenState extends State<VideoCoachScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final messages = await AiService.getCoachHistory(widget.videoId);
      if (!mounted) return;
      setState(() => _messages = messages);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _sending) return;

    _messageController.clear();

    setState(() {
      _sending = true;
      _error = null;
      _messages = [
        ..._messages,
        {
          'role': 'user',
          'message': message,
          'video_version': 1,
        },
      ];
    });
    _scrollToBottom();

    try {
      final result = await AiService.sendCoachMessage(
        videoId: widget.videoId,
        message: message,
        videoVersion: 1,
      );

      if (!mounted) return;

      setState(() {
        _messages = [
          ..._messages,
          {
            'role': 'coach',
            'message': result['response'] ?? '',
            'video_version': result['video_version'] ?? 1,
            'score': result['score'],
          },
        ];
      });
      _scrollToBottom();
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('AI Video Coach'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (_, index) {
                          return _messageBubble(_messages[index]);
                        },
                      ),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: AppColors.danger,
                  fontSize: 12,
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.monetization_on, size: 12, color: AppColors.coin),
                  const SizedBox(width: 3),
                  Text(
                    '${FeatureCoinCosts.coachMessage} per message',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 5,
                      enabled: !_sending,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Ask your Coach about this video...',
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.send,
                            color: AppColors.primary,
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 46,
              color: AppColors.secondary,
            ),
            const SizedBox(height: 14),
            const Text(
              'Your Video Coach',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask Viyo what worked, what needs improvement, '
              'or what you should change next.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            OutlinedButton(
              onPressed: () {
                _messageController.text =
                    'Analyze this video and tell me the most important thing I should improve.';
                _send();
              },
              child: const Text('Analyze my video'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> message) {
    final isUser = message['role'] == 'user';
    final score = message['score'];

    return Align(
      alignment: isUser
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: AppTheme.card(
          borderColor: isUser
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.secondary.withOpacity(0.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUser ? Icons.person_outline : Icons.auto_awesome,
                  size: 16,
                  color: isUser
                      ? AppColors.primary
                      : AppColors.secondary,
                ),
                const SizedBox(width: 7),
                Text(
                  isUser ? 'You' : 'Viyo Coach',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              message['message'] ?? '',
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (score != null) ...[
              const SizedBox(height: 10),
              Text(
                'Score: $score/100',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.coin,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
