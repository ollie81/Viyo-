import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import '../models/post.dart';

/// Public links to Viyo posts. www.viyo.site/p/<id> serves a preview page
/// (thumbnail, caption, creator) that WhatsApp, X, Facebook and search
/// engines can read, with a button that opens the post in the app.
class ShareLinks {
  static const site = 'https://www.viyo.site';

  static String postUrl(String postId) => '$site/p/$postId';

  /// Shares a post as its Viyo link plus a short line of its caption.
  static Future<void> sharePost(Post post) async {
    final caption = post.caption.trim().split('\n').first;
    final line = caption.isEmpty
        ? 'Watch this on Viyo'
        : (caption.length > 90 ? '${caption.substring(0, 87)}...' : caption);
    await Share.share(
      '$line\n${postUrl(post.id)}',
      subject: 'Viyo post by ${post.authorUsername ?? 'a creator'}',
    );
  }

  /// The post id a shared link opened the app with (/app/?post=<id>), once.
  static String? _pending = kIsWeb ? Uri.base.queryParameters['post'] : null;

  static String? takeOpenedPostId() {
    final id = _pending;
    _pending = null;
    if (id == null || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) return null;
    return id;
  }
}
