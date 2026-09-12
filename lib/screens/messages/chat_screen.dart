import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/conversation.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherName;
  final String? otherAvatarUrl;

  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherName,
    this.otherAvatarUrl,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Reversed list — "scrolled to the top of history" is actually
    // pixels near maxScrollExtent in a reverse ListView.
    if (_scrollController.position.pixels >
            _scrollController.position.maxScrollExtent - 200 &&
        !_loadingMore && _hasMore) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final messages = await MessagingService.getMessages(widget.conversationId);
      if (!mounted) return;
      setState(() => _messages = messages);
      // Best-effort — a creator opening the thread should clear the
      // badge even if this particular call hiccups.
      MessagingService.markRead(widget.conversationId).catchError((_) {});
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final older = await MessagingService.getMessages(
        widget.conversationId,
        before: _messages.first.createdAt,
      );
      if (!mounted) return;
      setState(() {
        if (older.isEmpty) _hasMore = false;
        _messages = [...older, ..._messages];
      });
    } catch (_) {
      // Silent — pagination failing just means older history doesn't
      // load on this scroll; the visible conversation is unaffected.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    _controller.clear();
    setState(() => _sending = true);
    try {
      final sent = await MessagingService.sendMessage(widget.conversationId, text);
      if (!mounted) return;
      setState(() => _messages = [..._messages, sent]);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      // Put the text back so nothing typed is lost to a failed send.
      _controller.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0); // reversed list — 0 is the bottom
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.surfaceBorder,
              backgroundImage: widget.otherAvatarUrl != null ? NetworkImage(widget.otherAvatarUrl!) : null,
              child: widget.otherAvatarUrl == null
                  ? Text(widget.otherName.isNotEmpty ? widget.otherName[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 13))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(widget.otherName, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
                        ),
                      )
                    : _messages.isEmpty
                        ? _emptyState()
                        : ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            itemCount: _messages.length + (_loadingMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              // Reversed: index 0 is the newest, so the
                              // list itself is walked back-to-front.
                              final reverseIndex = _messages.length - 1 - i;
                              if (reverseIndex < 0) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                );
                              }
                              return _bubble(_messages[reverseIndex]);
                            },
                          ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(hintText: 'Message...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: AppColors.primary),
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
            const Icon(Icons.waving_hand_outlined, size: 40, color: AppColors.secondary),
            const SizedBox(height: 12),
            Text('Say hi to ${widget.otherName}', style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMessage m) {
    return Align(
      alignment: m.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: m.isMine ? AppColors.primary.withOpacity(0.18) : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: m.isMine ? AppColors.primary.withOpacity(0.35) : AppColors.surfaceBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.content, style: const TextStyle(fontSize: 14, height: 1.35)),
            const SizedBox(height: 3),
            Text(
              timeago.format(m.createdAt),
              style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
