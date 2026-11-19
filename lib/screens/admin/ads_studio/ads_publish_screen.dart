import 'package:flutter/material.dart';
import '../../../models/ad_campaign.dart';
import '../../../services/ads_studio_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/ad_post_extras.dart';
import 'promote_sheet.dart';

/// Publish a finished ad on VIYO: caption, category, product information, link, thumbnail, a preview of
/// the post, then public or private. The post plays the same video (nothing is uploaded again), is always
/// labelled as an ad, and the creator keeps the ad: they can still download it and post it anywhere.
class AdsPublishScreen extends StatefulWidget {
  final String adminKey;
  final AdCampaign campaign;
  const AdsPublishScreen({super.key, required this.adminKey, required this.campaign});

  @override
  State<AdsPublishScreen> createState() => _AdsPublishScreenState();
}

class _AdsPublishScreenState extends State<AdsPublishScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  AdPublishOptions? _options;
  AdPublished? _published;

  final _caption = TextEditingController();
  final _info = TextEditingController();
  final _link = TextEditingController();
  String _category = 'other';
  String _thumbnail = 'video';
  bool _public = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    _info.dispose();
    _link.dispose();
    super.dispose();
  }

  String _msg(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o = await AdsStudioService.publishOptions(widget.adminKey, widget.campaign.id);
      final p = o.published;
      _options = o;
      _published = p;
      _caption.text = p?.caption ?? o.suggested['caption'] ?? '';
      _info.text = p?.productInfo ?? o.suggested['product_info'] ?? '';
      _link.text = p?.link ?? o.suggested['link'] ?? '';
      _category = p?.category ?? o.suggested['category'] ?? 'other';
      if (!o.categories.any((c) => c.key == _category)) _category = 'other';
      _public = p == null ? true : p.public || p.archived;
      if (o.thumbnails.isNotEmpty && !o.thumbnails.any((t) => t['key'] == _thumbnail)) {
        _thumbnail = o.thumbnails.first['key']!;
      }
    } catch (e) {
      _error = _msg(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _thumbUrl {
    final t = _options?.thumbnails.where((t) => t['key'] == _thumbnail);
    return (t == null || t.isEmpty) ? null : t.first['url'];
  }

  Future<void> _publish() async {
    setState(() => _saving = true);
    try {
      final p = await AdsStudioService.publish(
        widget.adminKey,
        widget.campaign.id,
        caption: _caption.text.trim(),
        category: _category,
        link: _link.text.trim(),
        productInfo: _info.text.trim(),
        thumbnail: _thumbnail,
        public: _public,
      );
      if (!mounted) return;
      setState(() => _published = p);
      _snack(p.public ? 'Published on VIYO.' : 'Saved as a private post: only you can see it.');
    } catch (e) {
      if (mounted) _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _takeDown() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Take this ad off VIYO?'),
        content: const Text('The post is hidden from everyone. Your ad, its likes and comments are kept, '
            'and you can publish it again any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Take down')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      final p = await AdsStudioService.unpublish(widget.adminKey, widget.campaign.id);
      if (!mounted) return;
      setState(() => _published = p);
      _snack('Taken off VIYO.');
    } catch (e) {
      if (mounted) _snack(_msg(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.background, title: const Text('Publish to VIYO')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _errorView()
              : _content(),
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ]),
        ),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 18),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
      );

  Widget _content() {
    final o = _options!;
    if (!o.canPublish) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Only a finished ad that passed the quality check can be published.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
      children: [
        if (_published != null) _statusBanner(_published!),
        _label('Preview'),
        Center(child: _preview()),
        _label('Caption'),
        TextField(
          controller: _caption,
          maxLines: 3,
          maxLength: 2200,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'What should people know?'),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        _label('Category'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: o.categories
              .map((c) => ChoiceChip(
                    label: Text(c.value, style: const TextStyle(fontSize: 12)),
                    selected: _category == c.key,
                    onSelected: (_) => setState(() => _category = c.key),
                  ))
              .toList(),
        ),
        _label('Product information'),
        TextField(
          controller: _info,
          maxLines: 2,
          maxLength: 600,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'Prices, features: only what is true'),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        _label('Website or contact link'),
        TextField(
          controller: _link,
          onChanged: (_) => setState(() {}),
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(hintText: 'yourbrand.com, tel:+250..., mailto:...'),
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
        if (o.thumbnails.isNotEmpty) ...[
          _label('Thumbnail'),
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: o.thumbnails.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final t = o.thumbnails[i];
                final selected = t['key'] == _thumbnail;
                return GestureDetector(
                  onTap: () => setState(() => _thumbnail = t['key']!),
                  child: Container(
                    width: 70,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: selected ? AppColors.primary : AppColors.surfaceBorder, width: 2),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network(t['url']!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface)),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            color: Colors.black54,
                            padding: const EdgeInsets.all(2),
                            child: Text(t['label']!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9, color: Colors.white)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        _label('Who can see it'),
        Container(
          decoration: AppTheme.card(),
          child: Column(children: [
            RadioListTile<bool>(
              value: true,
              groupValue: _public,
              onChanged: (v) => setState(() => _public = v!),
              title: const Text('Public', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('Anyone on VIYO, labelled as an ad', style: TextStyle(fontSize: 11.5)),
            ),
            RadioListTile<bool>(
              value: false,
              groupValue: _public,
              onChanged: (v) => setState(() => _public = v!),
              title: const Text('Private', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('Only you, on your profile', style: TextStyle(fontSize: 11.5)),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _publish,
            child: Text(_saving
                ? 'Saving...'
                : _published == null || _published!.archived
                    ? (_public ? 'Publish' : 'Save as private post')
                    : 'Save changes'),
          ),
        ),
        if (_published != null && _published!.public) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      if (await showPromoteSheet(context, _published!.postId) && mounted) {
                        _snack('Promotion started. It is labelled "Promoted" and you can stop it any time.');
                      }
                    },
              icon: const Icon(Icons.campaign_outlined, size: 16),
              label: const Text('Promote with coins'),
            ),
          ),
        ],
        if (_published != null && !_published!.archived) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: _saving ? null : _takeDown, child: const Text('Take off VIYO')),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Publishing on VIYO is not exclusive. You keep your ad and can download it from the previous screen.',
          style: TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
      ],
    );
  }

  Widget _statusBanner(AdPublished p) {
    final (text, color) = p.archived
        ? ('Taken off VIYO', AppColors.textMuted)
        : p.public
            ? ('Live on VIYO', AppColors.success)
            : ('Private post: only you can see it', AppColors.coin);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13))),
      ]),
    );
  }

  /// Roughly how the post looks in the feed: the thumbnail, the Ad label, caption, product info, Visit.
  Widget _preview() {
    final landscape = widget.campaign.aspectRatio == '16:9';
    final square = widget.campaign.aspectRatio == '1:1';
    final w = landscape ? 300.0 : (square ? 240.0 : 200.0);
    final h = landscape ? w * 9 / 16 : (square ? w : w * 16 / 9);
    final url = _thumbUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(fit: StackFit.expand, children: [
          if (url != null)
            Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.surface))
          else
            const ColoredBox(color: AppColors.surface),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87],
                stops: [0.45, 1],
              ),
            ),
          ),
          const Center(child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 42)),
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              const Row(children: [
                Text('You', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                SizedBox(width: 6),
                AdLabel(),
              ]),
              if (_caption.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(_caption.text.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11)),
                ),
              if (_info.text.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(_info.text.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 10)),
                ),
              if (AdVisitButton.uriFor(_link.text) != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: IgnorePointer(child: AdVisitButton(link: _link.text)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
