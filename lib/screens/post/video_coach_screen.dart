import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/coach_video_context.dart';
import '../../models/insufficient_coins_exception.dart';
import '../../services/ai_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/coach_markdown.dart';
import '../../widgets/insufficient_coins_sheet.dart';

/// Persistent Coach conversation attached to one specific video.
/// The backend stores the history in Supabase, so leaving the screen
/// and reopening the same video does not erase the conversation.
class VideoCoachScreen extends StatefulWidget {
  final String videoId;

  /// What the AI repurposer measured about this clip.
  ///
  /// For a posted video the backend resolves the caption, the real
  /// engagement numbers and the viewers' own comments itself. For a clip
  /// that only exists in the repurposer there is no post row yet, so
  /// this is the only way the Coach can see the transcript, the hook and
  /// the analyzer's verdict — without it, it is answering about a video
  /// it has never seen.
  final CoachVideoContext? videoContext;

  const VideoCoachScreen({
    super.key,
    required this.videoId,
    this.videoContext,
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

  /// The reply currently arriving token by token. Null when nothing is
  /// streaming; empty-but-not-null means the turn has started and the
  /// typing indicator should show.
  String? _streamingReply;
  StreamSubscription<CoachStreamEvent>? _streamSub;

  /// Tappable follow-ups from the most recent reply.
  List<String> _suggestions = const [];

  static const List<String> _openers = [
    'What is the single biggest problem with this video?',
    'Is my hook strong enough in the first 2 seconds?',
    'Score this video out of 100 and explain why.',
    'Write me a better caption for this.',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _streamSub?.cancel();
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
      setState(() => _error = _readable(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Server detail strings arrive wrapped in "Exception: " — the creator
  /// should read the problem, not Dart's punctuation.
  String _readable(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> _send([String? preset]) async {
    final message = (preset ?? _messageController.text).trim();
    if (message.isEmpty || _sending) return;

    _messageController.clear();

    setState(() {
      _sending = true;
      _error = null;
      _suggestions = const [];
      _streamingReply = '';
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

    var buffer = '';
    List<String> suggestions = const [];
    String? warning;

    try {
      final stream = AiService.streamCoachMessage(
        videoId: widget.videoId,
        message: message,
        videoVersion: 1,
        videoContext: widget.videoContext,
      );

      final completer = Completer<void>();
      _streamSub = stream.listen(
        (event) {
          if (event.error != null) {
            // Generation died after the stream opened. The backend has
            // already handed the coins back; say so rather than leaving
            // the creator wondering what they paid for.
            if (mounted) {
              setState(() => _error =
                  '${event.error}\nYour coins for this message were refunded.');
            }
            return;
          }

          if (event.replace != null) {
            buffer = event.replace!;
          } else if (event.delta != null) {
            buffer += event.delta!;
          }

          if (event.done) {
            suggestions = event.suggestions;
            warning = event.warning;
          }

          if (mounted) {
            setState(() => _streamingReply = buffer);
            _scrollToBottom();
          }
        },
        onError: completer.completeError,
        onDone: completer.complete,
        cancelOnError: true,
      );

      await completer.future;

      if (!mounted) return;

      if (buffer.isNotEmpty) {
        setState(() {
          _messages = [
            ..._messages,
            {
              'role': 'coach',
              'message': buffer,
              'video_version': 1,
            },
          ];
          _suggestions = suggestions;
          if (warning != null) _error = warning;
        });
      }
    } on InsufficientCoinsException catch (e) {
      if (mounted) showInsufficientCoinsSheet(context, e);
    } catch (e) {
      if (!mounted) return;
      // A stream that dies mid-answer still delivered real coaching —
      // keep what arrived instead of throwing it away with the error.
      setState(() {
        if (buffer.isNotEmpty) {
          _messages = [
            ..._messages,
            {'role': 'coach', 'message': buffer, 'video_version': 1},
          ];
        }
        _error = _readable(e);
      });
    } finally {
      await _streamSub?.cancel();
      _streamSub = null;
      if (mounted) {
        setState(() {
          _sending = false;
          _streamingReply = null;
        });
        _scrollToBottom();
      }
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
    final streaming = _streamingReply;
    final itemCount = _messages.length + (streaming != null ? 1 : 0);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('AI Video Coach'),
        bottom: widget.videoContext != null
            ? const PreferredSize(
                preferredSize: Size.fromHeight(26),
                child: _SeesVideoBanner(),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty && streaming == null
                    ? _emptyState()
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: itemCount,
                        itemBuilder: (_, index) {
                          if (index < _messages.length) {
                            return _messageBubble(_messages[index]);
                          }
                          return _messageBubble(
                            {'role': 'coach', 'message': streaming},
                            isStreaming: true,
                          );
                        },
                      ),
          ),

          if (_suggestions.isNotEmpty && !_sending) _suggestionChips(),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.monetization_on, size: 12, color: AppColors.coin),
                  SizedBox(width: 3),
                  Text(
                    '${FeatureCoinCosts.coachMessage} per message',
                    style: TextStyle(fontSize: 11, color: AppColors.textMuted),
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
                    onPressed: _sending ? null : () => _send(),
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

  Widget _suggestionChips() {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => _SuggestionChip(
          label: _suggestions[i],
          onTap: () => _send(_suggestions[i]),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
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
          Text(
            widget.videoContext != null
                ? 'It has read your transcript, your hook and the analyzer\'s '
                    'notes on this clip. Ask it anything.'
                : 'Ask Viyo what worked, what needs improvement, '
                    'or what you should change next.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          ..._openers.map(
            (opener) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _sending ? null : () => _send(opener),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                  ),
                  child: Text(opener, textAlign: TextAlign.left),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(Map<String, dynamic> message, {bool isStreaming = false}) {
    final isUser = message['role'] == 'user';
    final score = message['score'];
    final text = (message['message'] ?? '') as String;

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

            // The very first moment of a streamed reply has no text yet —
            // show the Coach thinking rather than an empty bubble.
            if (isStreaming && text.isEmpty)
              const _TypingDots()
            else if (isUser)
              Text(text, style: const TextStyle(fontSize: 14, height: 1.45))
            else
              CoachMarkdown(text: text),

            if (score != null) ...[
              const SizedBox(height: 10),
              _ScoreBadge(score: score is int ? score : int.tryParse('$score') ?? 0),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tells the creator, before they spend a coin, that this conversation is
/// grounded in their actual video — the Coach used to be unable to see it
/// at all, and there was no way to know that from the screen.
class _SeesVideoBanner extends StatelessWidget {
  const _SeesVideoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.center,
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 13, color: AppColors.success),
          SizedBox(width: 5),
          Text(
            'Coach has watched this video',
            style: TextStyle(fontSize: 11, color: AppColors.success),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.north_east, size: 12, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBadge extends StatelessWidget {
  final int score;

  const _ScoreBadge({required this.score});

  Color get _color {
    if (score >= 75) return AppColors.success;
    if (score >= 50) return AppColors.coin;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$score',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _color,
            height: 1,
          ),
        ),
        const Text(
          ' /100',
          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: score / 100,
              minHeight: 5,
              backgroundColor: AppColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation(_color),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three dots breathing in sequence while the first token is on its way.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            // Each dot runs a third of a cycle behind the one before it.
            final phase = (_controller.value - i * 0.18) % 1.0;
            final lift = (1 - (phase * 2 - 1).abs()).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(right: 5, top: 4, bottom: 4),
              child: Transform.translate(
                offset: Offset(0, -3 * lift),
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.secondary
                        .withOpacity(0.35 + 0.55 * lift),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
