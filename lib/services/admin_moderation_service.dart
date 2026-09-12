import 'dart:convert';
import 'package:http/http.dart' as http;
import '../constants/supabase_constants.dart';

class ReportContext {
  final bool exists;
  final String? caption;
  final String? mediaUrl;
  final String? username;
  final String? displayName;
  final String? ownerId;

  ReportContext({
    this.exists = true,
    this.caption,
    this.mediaUrl,
    this.username,
    this.displayName,
    this.ownerId,
  });

  factory ReportContext.fromJson(Map<String, dynamic> json) => ReportContext(
        exists: json['exists'] ?? true,
        caption: json['caption'],
        mediaUrl: json['media_url'],
        username: json['username'],
        displayName: json['display_name'],
        ownerId: json['owner_id'],
      );
}

class Report {
  final String id;
  final String reporterId;
  final String? reporterUsername;
  final String targetType;
  final String targetId;
  final String reason;
  final String? details;
  final String status;
  final DateTime createdAt;
  final ReportContext context;

  Report({
    required this.id,
    required this.reporterId,
    this.reporterUsername,
    required this.targetType,
    required this.targetId,
    required this.reason,
    this.details,
    required this.status,
    required this.createdAt,
    required this.context,
  });

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'],
        reporterId: json['reporter_id'],
        reporterUsername: json['reporter_username'],
        targetType: json['target_type'],
        targetId: json['target_id'],
        reason: json['reason'],
        details: json['details'],
        status: json['status'],
        createdAt: DateTime.parse(json['created_at']).toLocal(),
        context: ReportContext.fromJson(json['context'] ?? {}),
      );
}

/// Talks to viyo_ai's moderation.py — the admin-only report review
/// endpoints, gated by the shared X-Admin-Key header (the same
/// mechanism analytics.py already uses; there's no per-user admin role
/// anywhere else in this app). The key lives only in memory for this
/// screen's lifetime — never written to disk — so it has to be
/// re-entered each time the hidden entry point is used.
class AdminModerationService {
  static Future<List<Report>> listReports(String adminKey, {String status = 'pending'}) async {
    final res = await http.get(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/reports?status=$status'),
      headers: {'X-Admin-Key': adminKey},
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not load reports (${res.statusCode})');
    }
    final data = jsonDecode(res.body);
    return ((data['reports'] as List?) ?? [])
        .map((r) => Report.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// [action] is one of "dismiss", "remove_post", "ban_user".
  static Future<void> resolveReport(String adminKey, String reportId, String action) async {
    final res = await http.post(
      Uri.parse('${AiBackendConstants.baseUrl}/api/v1/admin/reports/$reportId/resolve'),
      headers: {'Content-Type': 'application/json', 'X-Admin-Key': adminKey},
      body: jsonEncode({'action': action}),
    );
    if (res.statusCode != 200) {
      throw Exception(_errorDetail(res) ?? 'Could not resolve report (${res.statusCode})');
    }
  }

  static String? _errorDetail(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      final detail = data is Map ? data['detail'] : null;
      return detail is String ? detail : null;
    } catch (_) {
      return null;
    }
  }
}
