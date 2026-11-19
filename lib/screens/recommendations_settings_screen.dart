import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/supabase_constants.dart';
import '../services/activity_service.dart';
import '../theme/app_theme.dart';

/// Your feed and your data: turn personal recommendations on/off, erase your watch history, and see any review
/// of your account (and appeal it). Nothing here is decided about you in secret.
class RecommendationsSettingsScreen extends StatefulWidget {
  const RecommendationsSettingsScreen({super.key});

  @override
  State<RecommendationsSettingsScreen> createState() => _RecommendationsSettingsScreenState();
}

class _RecommendationsSettingsScreenState extends State<RecommendationsSettingsScreen> {
  bool? _personalized;
  List<Map<String, dynamic>> _reviews = [];
  bool _busy = false;

  Map<String, String> get _headers {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    return {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'};
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ActivityService.personalized();
      if (mounted) setState(() => _personalized = p);
    } catch (_) {
      if (mounted) setState(() => _personalized = true);
    }
    try {
      final res = await http.get(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/account/reviews'), headers: _headers);
      if (res.statusCode == 200 && mounted) {
        setState(() => _reviews = [for (final r in jsonDecode(res.body) as List) Map<String, dynamic>.from(r as Map)]);
      }
    } catch (_) {}
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _toggle(bool on) async {
    setState(() => _personalized = on);
    try {
      await ActivityService.setPersonalized(on);
    } catch (e) {
      if (mounted) {
        setState(() => _personalized = !on);
        _snack('Could not save. Try again.');
      }
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Clear your watch history?'),
        content: const Text('Your For You page starts fresh. Your likes, follows and unlocked episodes stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ActivityService.clearHistory();
      if (mounted) _snack('History cleared.');
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _appeal(Map<String, dynamic> r) async {
    final text = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Appeal'),
        content: TextField(
          controller: text,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(hintText: 'Tell us what happened'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (send != true || text.text.trim().length < 5) return;
    final res = await http.post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/account/reviews/${r['id']}/appeal'),
        headers: _headers, body: jsonEncode({'text': text.text.trim()}));
    if (!mounted) return;
    _snack(res.statusCode == 200 ? 'Appeal sent. A person will read it.' : 'Could not send. Try again.');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Recommendations & history')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          decoration: AppTheme.card(),
          child: Column(children: [
            SwitchListTile(
              value: _personalized ?? true,
              onChanged: _personalized == null ? null : _toggle,
              title: const Text('Personal recommendations'),
              subtitle: const Text('Use what you watch, like and search to choose your For You page. '
                  'Off: everyone sees the same well-rated and new titles.', style: TextStyle(fontSize: 12)),
            ),
            const Divider(height: 1, color: AppColors.surfaceBorder),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Clear watch history'),
              subtitle: const Text('Start your recommendations fresh', style: TextStyle(fontSize: 12)),
              onTap: _busy ? null : _clear,
            ),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 12, 4, 0),
          child: Text(
            "Tip: tap ⋮ on a post and choose \"Not interested\" or \"Fewer from this creator\" to shape your feed.",
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Account reviews', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        if (_reviews.isEmpty)
          const Text('Nothing to review. 👍', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
        else
          for (final r in _reviews)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: AppTheme.card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((r['reason'] ?? '').toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('Status: ${r['status']}. ${r['effect'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if ((r['reviewed_note'] ?? '').toString().isNotEmpty)
                  Text('Reviewer: ${r['reviewed_note']}', style: const TextStyle(fontSize: 12)),
                if (r['status'] == 'open' && r['appeal'] == null)
                  Align(alignment: Alignment.centerRight,
                      child: TextButton(onPressed: () => _appeal(r), child: const Text('Appeal'))),
                if (r['appeal'] != null)
                  const Text('Appeal sent.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
      ]),
    );
  }
}
