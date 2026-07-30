// Named AppBadge (not Badge) to avoid clashing with Flutter's own
// material Badge widget.
class AppBadge {
  final String id;
  final String code;
  final String name;
  final String description;
  final double cost;
  final int tier;
  final String? iconUrl;
  final bool unlocked;

  AppBadge({
    required this.id,
    required this.code,
    required this.name,
    required this.description,
    required this.cost,
    required this.tier,
    this.iconUrl,
    this.unlocked = false,
  });

  factory AppBadge.fromJson(Map<String, dynamic> json) => AppBadge(
        id: json['id'],
        code: json['code'],
        name: json['name'],
        description: json['description'],
        cost: (json['cost'] as num?)?.toDouble() ?? 0,
        tier: json['tier'] ?? 1,
        iconUrl: json['icon_url'],
        unlocked: json['unlocked'] ?? false,
      );
}

