import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../services/watchlist_service.dart';
import '../theme/app_theme.dart';
import '../utils/friendly_error.dart';
import 'guest_gate.dart';

/// The save/bookmark toggle — shared between PostCard (targetType
/// 'post') and SeriesDetailScreen (targetType 'series') rather than
/// duplicated, since both need the same load/toggle/error state
/// machine. Manages its own state so callers (PostCard in particular,
/// which is otherwise stateless) don't need to become stateful just to
/// host this one control.
class WatchlistButton extends StatefulWidget {
  final String targetType;
  final String targetId;
  final double size;
  final Color? color;

  const WatchlistButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.size = 21,
    this.color,
  });

  @override
  State<WatchlistButton> createState() => _WatchlistButtonState();
}

class _WatchlistButtonState extends State<WatchlistButton> {
  bool? _saved; // null while the initial check is still loading
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _saved = false);
      return;
    }
    final saved = await WatchlistService.isSaved(userId, widget.targetType, widget.targetId);
    if (mounted) setState(() => _saved = saved);
  }

  Future<void> _toggle() async {
    if (_busy || _saved == null) return;
    if (!await GuestGate.allow(context, action: 'save to your watchlist')) return;
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    setState(() => _busy = true);
    try {
      if (_saved!) {
        await WatchlistService.remove(userId, widget.targetType, widget.targetId);
      } else {
        await WatchlistService.add(userId, widget.targetType, widget.targetId);
      }
      if (mounted) setState(() => _saved = !_saved!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = _saved ?? false;
    return IconButton(
      tooltip: saved ? 'Remove from watchlist' : 'Save to watchlist',
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _toggle,
      icon: Icon(
        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
        color: saved ? AppColors.secondary : (widget.color ?? AppColors.textSecondary),
        size: widget.size,
      ),
    );
  }
}
