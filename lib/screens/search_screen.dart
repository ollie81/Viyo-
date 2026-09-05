import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/profile_service.dart';
import '../../services/supabase_service.dart';
import '../../theme/app_theme.dart';
import 'profile/profile_screen.dart';
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  bool _hasQuery = false;
  Timer? _debounce;

  List<Map<String, dynamic>> _suggested = [];
  bool _loadingSuggested = true;

  @override
  void initState() {
    super.initState();
    _loadSuggested();
  }

  Future<void> _loadSuggested() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      setState(() => _loadingSuggested = false);
      return;
    }
    try {
      final suggested = await ProfileService.getSuggestedCreators(excludeUserId: userId);
      if (!mounted) return;
      setState(() {
        _suggested = suggested;
        _loadingSuggested = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingSuggested = false);
    }
  }

  void _onChanged(String value) {
    final hasQuery = value.trim().isNotEmpty;
    if (hasQuery != _hasQuery) setState(() => _hasQuery = hasQuery);
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
            Expanded(
              child: !_hasQuery
                  ? _SuggestedList(loading: _loadingSuggested, creators: _suggested)
                  : _loading
                      ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                      : _results.isEmpty
                          ? const _NoResultsState()
                          : ListView.builder(
                              itemCount: _results.length,
                              itemBuilder: (ctx, i) => _CreatorTile(creator: _results[i]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestedList extends StatelessWidget {
  final bool loading;
  final List<Map<String, dynamic>> creators;

  const _SuggestedList({required this.loading, required this.creators});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (creators.isEmpty) {
      return const _SearchPrompt();
    }
    return ListView(
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'SUGGESTED CREATORS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...creators.map((c) => _CreatorTile(creator: c)),
      ],
    );
  }
}

class _CreatorTile extends StatelessWidget {
  final Map<String, dynamic> creator;

  const _CreatorTile({required this.creator});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.surfaceBorder,
        backgroundImage:
            creator['avatar_url'] != null ? NetworkImage(creator['avatar_url']) : null,
        child: creator['avatar_url'] == null
            ? Text((creator['display_name'] ?? '?')[0].toUpperCase())
            : null,
      ),
      title: Text(creator['display_name'] ?? ''),
      subtitle: Text(
        '@${creator['username']}${creator['niche'] != null && creator['niche'] != '' ? ' · ${creator['niche']}' : ''}',
        style: const TextStyle(color: AppColors.textMuted),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ProfileScreen(userId: creator['id'])),
      ),
    );
  }
}

class _SearchPrompt extends StatelessWidget {
  const _SearchPrompt();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.explore_outlined, color: AppColors.primary, size: 26),
          ),
          const SizedBox(height: 14),
          const Text('Find creators to follow', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _NoResultsState extends StatelessWidget {
  const _NoResultsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('No creators found', style: TextStyle(color: AppColors.textMuted)),
    );
  }
}
