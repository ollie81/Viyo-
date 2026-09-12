import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/admin_moderation_service.dart';
import '../../theme/app_theme.dart';

/// Solo-operator report review — not linked from anywhere in the app's
/// normal navigation. Reached only via the hidden long-press on the
/// Settings screen title (see settings_screen.dart), which is enough
/// friction that a regular user won't stumble into it; the real
/// protection is the admin key itself, which this screen asks for
/// every time rather than persisting it to disk.
class ModerationReviewScreen extends StatefulWidget {
  const ModerationReviewScreen({super.key});

  @override
  State<ModerationReviewScreen> createState() => _ModerationReviewScreenState();
}

class _ModerationReviewScreenState extends State<ModerationReviewScreen> {
  final _keyController = TextEditingController();
  String? _adminKey;
  List<Report> _reports = [];
  bool _loading = false;
  String? _error;
  final Set<String> _acting = {};

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _adminKey = key;
      _error = null;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_adminKey == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final reports = await AdminModerationService.listReports(_adminKey!);
      if (!mounted) return;
      setState(() => _reports = reports);
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      setState(() {
        _error = message;
        // A wrong key should send the creator back to the key prompt,
        // not leave them staring at a permanent error on a screen that
        // looks unlocked.
        if (message.contains('Invalid admin key')) _adminKey = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _act(Report report, String action, String confirmMessage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Are you sure?'),
        content: Text(confirmMessage),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action == 'dismiss' ? 'Dismiss' : 'Confirm',
                style: const TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _acting.add(report.id));
    try {
      await AdminModerationService.resolveReport(_adminKey!, report.id, action);
      if (!mounted) return;
      setState(() => _reports.removeWhere((r) => r.id == report.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst(RegExp(r'^Exception:\s*'), ''))),
      );
    } finally {
      if (mounted) setState(() => _acting.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Moderation')),
      body: _adminKey == null ? _keyPrompt() : _reportList(),
    );
  }

  Widget _keyPrompt() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.admin_panel_settings_outlined, size: 40, color: AppColors.textMuted),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Admin key'),
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _unlock, child: const Text('Unlock')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reportList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: const TextStyle(color: AppColors.danger), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_reports.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 100),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 40, color: AppColors.success),
                  SizedBox(height: 12),
                  Text('No pending reports', style: TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(14),
        itemCount: _reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _reportCard(_reports[i]),
      ),
    );
  }

  Widget _reportCard(Report r) {
    final busy = _acting.contains(r.id);
    final gone = !r.context.exists;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppTheme.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  r.targetType.toUpperCase(),
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.secondary),
                ),
              ),
              const SizedBox(width: 8),
              Text(r.reason, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(timeago.format(r.createdAt), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(height: 8),
          if (gone)
            const Text('This content no longer exists.', style: TextStyle(color: AppColors.textMuted, fontSize: 13))
          else if (r.targetType == 'post') ...[
            if ((r.context.caption ?? '').isNotEmpty)
              Text('"${r.context.caption}"', style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Text('by @${r.context.username ?? 'unknown'}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ] else
            Text('@${r.context.username ?? 'unknown'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          if ((r.details ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(r.details!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 6),
          Text('reported by @${r.reporterUsername ?? 'unknown'}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 12),
          if (busy)
            const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2)))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _act(r, 'dismiss', 'Dismiss this report with no action?'),
                  child: const Text('Dismiss'),
                ),
                if (r.targetType == 'post' && !gone)
                  OutlinedButton(
                    onPressed: () => _act(r, 'remove_post', 'Permanently delete this post?'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Remove post'),
                  ),
                if (!gone || r.targetType == 'user')
                  OutlinedButton(
                    onPressed: () => _act(
                      r, 'ban_user',
                      r.targetType == 'post'
                          ? 'Ban @${r.context.username ?? 'this user'} (the author of this post)?'
                          : 'Ban @${r.context.username ?? 'this user'}?',
                    ),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                    child: const Text('Ban user'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
