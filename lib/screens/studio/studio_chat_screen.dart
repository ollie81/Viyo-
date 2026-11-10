import 'package:flutter/material.dart';

import '../../services/creator_studio_service.dart';
import '../../theme/app_theme.dart';
import 'studio_widgets.dart';

/// The Studio assistant: chat with Viyo about this production. It sees the
/// saved project, remembers the conversation, and suggests changes as cards
/// the creator applies (free changes) or checks the price for (paid steps).
class StudioChatScreen extends StatefulWidget {
  final String projectId;
  final String projectTitle;
  /// Sent as soon as the chat opens (e.g. the idea typed on the Studio home).
  final String? initialMessage;
  /// Starts a paid step through the Studio's normal price check. Returns true
  /// if it was started. 'production' means: open Make the whole film.
  final Future<bool> Function(String job) onPaidStep;
  const StudioChatScreen(
      {super.key, required this.projectId, required this.projectTitle, this.initialMessage, required this.onPaidStep});

  @override
  State<StudioChatScreen> createState() => _StudioChatScreenState();
}

class _Pending {
  final String text, requestId;
  String? error;
  _Pending(this.text, this.requestId);
}

class _StudioChatScreenState extends State<StudioChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<StudioChatMessage> _messages = [];
  List<String> _suggestions = [];
  List<Map<String, dynamic>> _conversations = [];
  String? _conversationId;
  String _priceNote = '';
  bool _loading = true;
  String? _loadError;
  _Pending? _pending;
  final Set<String> _busyProposals = {};

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      final first = widget.initialMessage?.trim();
      if (first != null && first.isNotEmpty && mounted) _send(first);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({String? conversationId}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final j = await CreatorStudioService.chatHistory(widget.projectId, conversationId: conversationId);
      if (!mounted) return;
      setState(() {
        _messages = ((j['messages'] as List?) ?? []).map((m) => StudioChatMessage.fromJson(m as Map)).toList();
        _suggestions = ((j['suggestions'] as List?) ?? []).map((e) => '$e').toList();
        _conversations = ((j['conversations'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _conversationId = (j['conversation'] as Map?)?['id'];
        _priceNote = '${j['price_note'] ?? ''}';
        _loading = false;
      });
      _toBottom();
    } on StudioException catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.message;
          _loading = false;
        });
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent + 200,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String text, {_Pending? retry}) async {
    final msg = text.trim();
    if (msg.isEmpty || (_pending != null && retry == null)) return;
    final p = retry ?? _Pending(msg, CreatorStudioService.newRequestId());
    setState(() {
      p.error = null;
      _pending = p;
      if (retry == null) _input.clear();
    });
    _toBottom();
    try {
      final j = await CreatorStudioService.chatSend(widget.projectId, p.text, p.requestId, conversationId: _conversationId);
      if (!mounted) return;
      setState(() {
        if (j['message'] != null) _messages.add(StudioChatMessage.fromJson(j['message'] as Map));
        _messages.add(StudioChatMessage.fromJson(j['reply'] as Map));
        _conversationId = j['conversation_id'] ?? _conversationId;
        _pending = null;
      });
      _toBottom();
    } on StudioException catch (e) {
      if (!mounted) return;
      setState(() => p.error = e.notEnoughCredits ? 'Not enough credits for the assistant. Add credits, then retry.' : e.message);
    }
  }

  Future<void> _newChat() async {
    try {
      final j = await CreatorStudioService.chatNew(widget.projectId);
      if (!mounted) return;
      setState(() {
        _conversationId = (j['conversation'] as Map)['id'];
        _messages = [];
      });
      await _load(conversationId: _conversationId);
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  Future<void> _apply(StudioChatMessage m, int i) async {
    final prop = m.proposals[i];
    final key = '${m.id}:$i';
    setState(() => _busyProposals.add(key));
    try {
      if (prop['paid'] == true) {
        final started = await widget.onPaidStep('${prop['job']}');
        if (started) {
          await CreatorStudioService.setProposalStatus(m.id, i, 'started');
          setState(() => m.proposals[i] = {...prop, 'status': 'started'});
        }
      } else {
        final j = await CreatorStudioService.applyProposal(m.id, i);
        if (!mounted) return;
        setState(() => m.proposals[i] = Map<String, dynamic>.from(j['proposal'] as Map));
        showStudioInfo(context, '${j['result']}');
      }
    } on StudioException catch (e) {
      if (!mounted) return;
      setState(() => m.proposals[i] = {...prop, 'error': e.message});
      showStudioError(context, e.message);
    } finally {
      if (mounted) setState(() => _busyProposals.remove(key));
    }
  }

  Future<void> _dismiss(StudioChatMessage m, int i) async {
    try {
      await CreatorStudioService.setProposalStatus(m.id, i, 'dismissed');
      if (mounted) setState(() => m.proposals[i] = {...m.proposals[i], 'status': 'dismissed'});
    } on StudioException catch (e) {
      if (mounted) showStudioError(context, e.message);
    }
  }

  // ---------------------------------------------------------------- UI

  Widget _bubble(StudioChatMessage m) {
    final mine = m.mine;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary.withValues(alpha: 0.18) : StudioColors.panel,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              border: Border.all(color: mine ? AppColors.primary.withValues(alpha: 0.35) : StudioColors.panelBorder),
            ),
            child: SelectableText(m.content, style: const TextStyle(fontSize: 14.5, height: 1.45)),
          ),
          for (var i = 0; i < m.proposals.length; i++) _proposal(m, i),
        ]),
      ),
    );
  }

  Widget _proposal(StudioChatMessage m, int i) {
    final p = m.proposals[i];
    final status = '${p['status'] ?? 'proposed'}';
    final paid = p['paid'] == true;
    final busy = _busyProposals.contains('${m.id}:$i');
    final (label, color) = switch (status) {
      'applied' => ('Saved', AppColors.success),
      'started' => ('Started', AppColors.success),
      'dismissed' => ('Dismissed', AppColors.textMuted),
      _ => (paid ? 'Costs credits' : 'Suggestion', paid ? AppColors.coin : AppColors.primary),
    };
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        color: color.withValues(alpha: 0.06),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${p['title']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ]),
        if ('${p['summary'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${p['summary']}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
        ],
        if (status == 'applied' && p['result'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${p['result']}', style: const TextStyle(color: AppColors.success, fontSize: 12)),
          ),
        if (status == 'proposed' && p['error'] != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${p['error']}', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
          ),
        if (status == 'proposed')
          Wrap(spacing: 6, children: [
            TextButton(
              onPressed: busy ? null : () => _apply(m, i),
              child: Text(busy ? 'Working…' : paid ? 'See price' : 'Apply'),
            ),
            TextButton(onPressed: busy ? null : () => _dismiss(m, i), child: const Text('Dismiss')),
          ])
        else
          const SizedBox(height: 4),
      ]),
    );
  }

  Widget _typing() => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: StudioColors.panel, borderRadius: BorderRadius.circular(16)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Viyo is thinking…', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
          ]),
        ),
      );

  Widget _empty() => Padding(
        padding: const EdgeInsets.fromLTRB(4, 24, 4, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 30),
          const SizedBox(height: 10),
          const Text('Tell me your idea', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text(
            'One sentence is enough. I\'ll help you shape the story, characters and scenes, and suggest changes you can '
            'apply with one tap. Nothing changes unless you say so.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13.5, height: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in _suggestions)
              ActionChip(label: Text(s, style: const TextStyle(fontSize: 12.5)), onPressed: () => _send(s)),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Viyo assistant', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          Text(widget.projectTitle, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ]),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Chats',
            icon: const Icon(Icons.forum_outlined),
            color: StudioColors.panel,
            onSelected: (v) => v == '__new__' ? _newChat() : _load(conversationId: v),
            itemBuilder: (_) => [
              const PopupMenuItem(value: '__new__', child: Text('New chat')),
              if (_conversations.isNotEmpty) const PopupMenuDivider(),
              for (final c in _conversations)
                PopupMenuItem(
                  value: '${c['id']}',
                  child: Text('${(c['title'] as String?)?.isNotEmpty == true ? c['title'] : 'Chat'}'
                      '${c['id'] == _conversationId ? '  ✓' : ''}'),
                ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 780),
            child: Column(children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _loadError != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Text(_loadError!, textAlign: TextAlign.center),
                                const SizedBox(height: 10),
                                FilledButton(onPressed: () => _load(conversationId: _conversationId), child: const Text('Try again')),
                              ]),
                            ),
                          )
                        : ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), children: [
                            if (_messages.isEmpty && pending == null) _empty(),
                            for (final m in _messages) _bubble(m),
                            if (pending != null) ...[
                              Align(
                                alignment: Alignment.centerRight,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  constraints: const BoxConstraints(maxWidth: 560),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(pending.text, style: const TextStyle(fontSize: 14.5, height: 1.45)),
                                ),
                              ),
                              if (pending.error == null)
                                _typing()
                              else
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                                    Text(pending.error!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                                    TextButton(onPressed: () => _send(pending.text, retry: pending), child: const Text('Retry')),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _input.text = pending.text;
                                        _pending = null;
                                      }),
                                      child: const Text('Edit'),
                                    ),
                                  ]),
                                ),
                            ],
                          ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                decoration: const BoxDecoration(border: Border(top: BorderSide(color: StudioColors.panelBorder))),
                child: Column(children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        textInputAction: TextInputAction.newline,
                        decoration: studioField('Message Viyo', hint: 'Share an idea, ask for feedback, or say what to change')
                            .copyWith(counterText: ''),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: pending != null ? null : () => _send(_input.text),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                  ]),
                  if (_priceNote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(_priceNote, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
