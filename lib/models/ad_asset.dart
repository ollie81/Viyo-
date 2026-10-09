/// One reference image attached to a campaign (an uploaded screenshot,
/// product photo, branding asset, character image, or marketing
/// reference) — or a real VIYO screenshot pulled from the shared
/// library ([source] == 'viyo_library') instead of freshly uploaded.
class AdAsset {
  final String id;
  final String url;
  final String assetType;
  final String source;
  final String label;

  const AdAsset({
    required this.id,
    required this.url,
    required this.assetType,
    required this.source,
    required this.label,
  });

  factory AdAsset.fromJson(Map<String, dynamic> json) => AdAsset(
        id: json['id'] as String,
        url: json['url'] as String,
        assetType: json['asset_type'] ?? 'reference',
        source: json['source'] ?? 'uploaded',
        label: json['label'] ?? '',
      );
}
