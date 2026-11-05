import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/supabase_constants.dart';
import 'supabase_service.dart';

/// My Productions: a creator's own series and videos, and download links
/// for them (see creator_downloads.py on the backend).
///
/// The backend decides ownership from the signed-in account, hands out
/// short-lived links, and never deletes or changes anything — Viyo keeps
/// its stored copy no matter how often something is downloaded.
class ProductionEpisode {
  final String postId;
  final int? episodeNumber;
  final String title;
  final String? thumbnailUrl;
  final int? durationSeconds;
  final String watchStatus; // public | private | archived
  final bool downloadable;
  final String? notDownloadableReason;

  ProductionEpisode.fromJson(Map<String, dynamic> j)
      : postId = j['post_id'] as String,
        episodeNumber = j['episode_number'] as int?,
        title = (j['title'] as String?) ?? 'Untitled',
        thumbnailUrl = j['thumbnail_url'] as String?,
        durationSeconds = j['duration_seconds'] as int?,
        watchStatus = (j['watch_status'] as String?) ?? 'public',
        downloadable = j['downloadable'] == true,
        notDownloadableReason = j['not_downloadable_reason'] as String?;
}

class Production {
  final String id;
  final String kind; // series | video
  final String title;
  final String? contentType;
  final String? orientation;
  final String? status;
  final String? thumbnailUrl;
  final int episodeCount;
  final int publicEpisodeCount;
  final List<ProductionEpisode> episodes;

  bool get isSeries => kind == 'series';

  Production.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        kind = (j['kind'] as String?) ?? 'video',
        title = (j['title'] as String?) ?? 'Untitled',
        contentType = j['content_type'] as String?,
        orientation = j['orientation'] as String?,
        status = j['status'] as String?,
        thumbnailUrl = j['thumbnail_url'] as String?,
        episodeCount = (j['episode_count'] as int?) ?? 0,
        publicEpisodeCount = (j['public_episode_count'] as int?) ?? 0,
        episodes = ((j['episodes'] as List?) ?? [])
            .map((e) => ProductionEpisode.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
}

class DownloadLink {
  final String url;
  final String fileName;
  final String kind;
  final String source;
  final int? expiresAt;
  final String? quality;
  final String? orientation;
  final String? note;

  DownloadLink.fromJson(Map<String, dynamic> j)
      : url = j['url'] as String,
        fileName = j['file_name'] as String,
        kind = (j['kind'] as String?) ?? 'video',
        source = (j['source'] as String?) ?? 'supabase',
        expiresAt = j['expires_at'] as int?,
        quality = j['quality'] as String?,
        orientation = j['orientation'] as String?,
        note = j['note'] as String?;
}

class CreatorDownloadService {
  static String get _base => '${AiBackendConstants.baseUrl}/api/v1/creator';

  static Map<String, String> _headers() {
    final token = SupabaseService.client.auth.currentSession?.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Exception _error(http.Response res, String fallback) {
    try {
      final body = jsonDecode(res.body);
      final d = body is Map ? body['detail'] : null;
      if (d is String && d.isNotEmpty) return Exception(d);
    } catch (_) {}
    return Exception('$fallback (${res.statusCode})');
  }

  static Future<List<Production>> myProductions() async {
    final res = await http
        .get(Uri.parse('$_base/productions'), headers: _headers())
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw _error(res, "Couldn't load your productions");
    final list = (jsonDecode(res.body)['productions'] as List?) ?? [];
    return list.map((e) => Production.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  /// A fresh link every call, so a retry never reuses an expired one.
  static Future<DownloadLink> videoLink(String postId) => _link('$_base/downloads/$postId');

  static Future<DownloadLink> thumbnailLink(String postId) => _link('$_base/downloads/$postId/thumbnail');

  static Future<DownloadLink> _link(String url) async {
    final res = await http.post(Uri.parse(url), headers: _headers()).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) throw _error(res, "Couldn't prepare the download");
    return DownloadLink.fromJson(Map<String, dynamic>.from(jsonDecode(res.body) as Map));
  }
}
