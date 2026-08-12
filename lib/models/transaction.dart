class CoinTransaction {
  final String id;
  final double amount; // positive = earn, negative = spend
  final String type;
  final String description;
  final DateTime createdAt;

  CoinTransaction({
    required this.id,
    required this.amount,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  bool get isEarn => amount > 0;

  factory CoinTransaction.fromJson(Map<String, dynamic> json) =>
      CoinTransaction(
        id: json['id'],
        amount: (json['amount'] as num).toDouble(),
        type: json['type'],
        description: json['description'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
      );
}
