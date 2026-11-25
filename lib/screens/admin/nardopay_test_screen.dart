import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../constants/supabase_constants.dart';
import '../../theme/app_theme.dart';

/// Creates the admin test link on the server (a function so tests can replace it).
typedef TestLinkCall = Future<Map<String, dynamic>> Function(String adminKey, int amountRwf);

Future<Map<String, dynamic>> _createTestLink(String adminKey, int amountRwf) async {
  final res = await http
      .post(Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/nardopay/test-link'),
          headers: {'Content-Type': 'application/json', 'X-Admin-Key': adminKey},
          body: jsonEncode({'amount_rwf': amountRwf}))
      .timeout(const Duration(seconds: 30));
  final body = res.body.isEmpty ? null : jsonDecode(res.body);
  if (res.statusCode != 200) {
    final d = body is Map ? body['detail'] : null;
    throw Exception(d is String ? d : (d is Map ? '${d['message'] ?? d}' : 'Failed (${res.statusCode}).'));
  }
  return Map<String, dynamic>.from(body as Map);
}

/// Admin: a real NardoPay link that belongs to no VIYO order, to pay once and see the webhook NardoPay sends. It can
/// never credit coins. The admin key stays in memory only.
class NardopayTestScreen extends StatefulWidget {
  final TestLinkCall call;
  const NardopayTestScreen({super.key, this.call = _createTestLink});
  @override
  State<NardopayTestScreen> createState() => _NardopayTestScreenState();
}

class _NardopayTestScreenState extends State<NardopayTestScreen> {
  final _key = TextEditingController();
  final _amount = TextEditingController(text: '100');
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _key.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final amount = int.tryParse(_amount.text.trim()) ?? 0;
    if (_key.text.trim().isEmpty || amount < 100 || amount > 2000) {
      setState(() => _error = 'Enter the admin key and an amount between 100 and 2,000 RWF.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await widget.call(_key.text.trim(), amount);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final found = ((r?['links_found'] as List?) ?? const []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('NardoPay test payment')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text(
            'Creates a real NardoPay link that belongs to no VIYO order. Pay it once to see the message NardoPay sends '
            'to VIYO. It never adds coins.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        TextField(controller: _key, obscureText: true, decoration: const InputDecoration(labelText: 'Admin key')),
        TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Amount (RWF)')),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.link, size: 18),
          label: const Text('Create test link'),
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: AppColors.danger)),
          ),
        if (r != null) ...[
          const SizedBox(height: 16),
          const Text('Link created', style: TextStyle(fontWeight: FontWeight.w700)),
          SelectableText('${r['link']}', style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => launchUrl(Uri.parse('${r['link']}'), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Open and pay'),
          ),
          const SizedBox(height: 16),
          const Text('Where NardoPay put the link (send this to Claude):',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          for (final f in found) SelectableText('${f['field']}', style: const TextStyle(fontSize: 13)),
          Text('Amount sent to NardoPay: ${r['amount_sent']}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}
