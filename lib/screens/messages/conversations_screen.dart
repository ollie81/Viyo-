import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/conversation.dart';
import '../../services/messaging_service.dart';
import '../../theme/app_theme.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _conversations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final conversations = await MessagingService.getConversations();
      if (!mounted) return;
      setState(() => _conversations = conversations);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChat(Conversation c) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: c.id,
          otherUserId: c.otherUserId,
          otherName: c.otherName,
          otherAvatarUrl: c.otherAvatarUrl,
        ),
      ),
    );
    // The chat screen may have marked messages read or sent new ones —
    // refresh so the unread badge and preview are current when we're
    // back on this list.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('Messages'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorState()
                : _conversations.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: _conversations.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.surfaceBorder),
                        itemBuilder: (_, i) => _conversationTile(_conversations[i]),
                      ),
      ),
    );
  }

  Widget _errorState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.error_outline, size: 40, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(
            children: [
              const Icon(Icons.chat_bubble_outline, size: 46, color: AppColors.textMuted),
              const SizedBox(height: 14),
              const Text('No messages yet', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 6),
              const Text(
                'Message a creator from their profile to start a conversation.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _conversationTile(Conversation c) {
    final hasUnread = c.unreadCount > 0;
    return ListTile(
      onTap: () => _openChat(c),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.surfaceBorder,
        backgroundImage: c.otherAvatarUrl != null ? NetworkImage(c.otherAvatarUrl!) : null,
        child: c.otherAvatarUrl == null
            ? Text(c.otherName.isNotEmpty ? c.otherName[0].toUpperCase() : '?')
            : null,
      ),
      title: Text(
        c.otherName,
        style: TextStyle(fontWeight: hasUnread ? FontWeight.w800 : FontWeight.w600),
      ),
      subtitle: Text(
        c.lastMessagePreview == null
            ? 'Say hi 👋'
            : (c.lastMessageIsMine ? 'You: ${c.lastMessagePreview}' : c.lastMessagePreview!),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: hasUnread ? AppColors.textPrimary : AppColors.textSecondary,
          fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            timeago.format(c.lastMessageAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          if (hasUnread) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              constraints: const BoxConstraints(minWidth: 20),
              child: Text(
                '${c.unreadCount}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.background),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
