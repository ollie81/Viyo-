import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../theme/app_theme.dart';
import '../profile/profile_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  Timer? _debounce;

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
  }

  Future<void> _search(String value) async {
    if (value.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _loading = true);
    final results = await ProfileService.searchCreators(value.trim());
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Discover')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _query,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Search creators by name or username',
                prefixIcon: Icon(Icons.search, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(color: AppColors.primary),
            Expanded(
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.surfaceBorder,
                      backgroundImage: r['avatar_url'] != null ? NetworkImage(r['avatar_url']) : null,
                      child: r['avatar_url'] == null
                          ? Text((r['display_name'] ?? '?')[0].toUpperCase())
                          : null,
                    ),
                    title: Text(r['display_name'] ?? ''),
                    subtitle: Text('@${r['username']}${r['niche'] != null && r['niche'] != '' ? ' · ${r['niche']}' : ''}',
                        style: const TextStyle(color: AppColors.textMuted)),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProfileScreen(userId: r['id'])),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
