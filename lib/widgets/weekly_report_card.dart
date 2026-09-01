import 'package:flutter/material.dart';
import '../models/weekly_report.dart';
import '../services/ai_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'guest_gate.dart';

/// The Growth Dashboard's "how is this week going overall?" card —
/// rolls up Coach scores and post engagement for the last 7 days
/// instead of leaving the creator to piece that together from
/// individual post feedback.
class WeeklyReportCard extends StatefulWidget {
  const WeeklyReportCard({super.key});

  @override
  State<WeeklyReportCard> createState() => _WeeklyReportCardState();
}

class _WeeklyReportCardState extends State<WeeklyReportCard> {
  WeeklyReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Guests never trigger the request at all — this fires automatically
    // on dashboard load, and AI features are account-gated.
    if (SupabaseService.isGuest) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final report = await AiService.getWeeklyReport();
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Could not load this week's report";
        _loading = false;
      });
    }
  }

  IconData? get _trendIcon {
    switch (_report?.scoreTrend) {
      case 'up':
        return Icons.trending_up;
      case 'down':
        return Icons.trending_down;
      case 'flat':
        return Icons.trending_flat;
      default:
        return null;
    }
  }

  Color get _trendColor {
    switch (_report?.scoreTrend) {
      case 'up':
        return AppColors.success;
      case 'down':
        return AppColors.danger;
      default:
        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    // A failed load is quietly skipped (not worth a dashboard error
    // banner over a secondary widget), but loading and success both
    // show the same card shell so nothing pops into a fresh layout.
    if (_error != null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glowCard(glowColor: AppColors.success, glowOpacity: 0.16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.fact_check_outlined, size: 16, color: AppColors.success),
              SizedBox(width: 6),
              Text(
                'WEEKLY REPORT CARD',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (SupabaseService.isGuest)
            GestureDetector(
              onTap: () async {
                if (await GuestGate.allow(context, action: 'see your weekly report')) _load();
              },
              child: const Text(
                'Create an account to track your weekly progress',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12, decoration: TextDecoration.underline),
              ),
            )
          else if (_loading || _report == null)
            const SizedBox(
              height: 40,
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.success),
                ),
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(child: _stat('Posts', '${_report!.postsThisWeek}')),
                Expanded(
                  child: _stat(
                    'Avg score',
                    _report!.avgScoreThisWeek != null ? _report!.avgScoreThisWeek!.toStringAsFixed(0) : '—',
                    trailingIcon: _trendIcon,
                    trailingColor: _trendColor,
                  ),
                ),
                Expanded(child: _stat('Likes + comments', '${_report!.totalLikes + _report!.totalComments}')),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _report!.summary,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, {IconData? trailingIcon, Color? trailingColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (trailingIcon != null) ...[
              const SizedBox(width: 2),
              Icon(trailingIcon, size: 14, color: trailingColor),
            ],
          ],
        ),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
      ],
    );
  }
}
