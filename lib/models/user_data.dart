class Mission {
  final String id;
  final String title;
  final String description;
  final int coins;
  final String type;
  bool completed;

  Mission({
    required this.id,
    required this.title,
    required this.description,
    required this.coins,
    required this.type,
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'coins': coins,
        'type': type,
        'completed': completed,
      };

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'],
        title: json['title'],
        description: json['description'],
        coins: json['coins'],
        type: json['type'],
        completed: json['completed'] ?? false,
      );
}

class Transaction {
  final String id;
  final String type;
  final int amount;
  final String description;
  final String date;

  Transaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.date,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'amount': amount,
        'description': description,
        'date': date,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
        id: json['id'],
        type: json['type'],
        amount: json['amount'],
        description: json['description'],
        date: json['date'],
      );
}

class Badge {
  final String id;
  final String name;
  final String description;
  final int cost;
  bool unlocked;

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.cost,
    this.unlocked = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'cost': cost,
        'unlocked': unlocked,
      };

  factory Badge.fromJson(Map<String, dynamic> json) => Badge(
        id: json['id'],
        name: json['name'],
        description: json['description'],
        cost: json['cost'],
        unlocked: json['unlocked'] ?? false,
      );
}

class UserData {
  String name;
  int coins;
  int streak;
  String lastLogin;
  List<Mission> missions;
  List<Transaction> transactions;
  List<Badge> badges;
  int gifted;

  UserData({
    required this.name,
    this.coins = 0,
    this.streak = 0,
    this.lastLogin = '',
    required this.missions,
    required this.transactions,
    required this.badges,
    this.gifted = 0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'coins': coins,
        'streak': streak,
        'lastLogin': lastLogin,
        'missions': missions.map((m) => m.toJson()).toList(),
        'transactions': transactions.map((t) => t.toJson()).toList(),
        'badges': badges.map((b) => b.toJson()).toList(),
        'gifted': gifted,
      };

  factory UserData.fromJson(Map<String, dynamic> json) => UserData(
        name: json['name'] ?? 'Creator',
        coins: json['coins'] ?? 0,
        streak: json['streak'] ?? 0,
        lastLogin: json['lastLogin'] ?? '',
        missions: (json['missions'] as List? ?? [])
            .map((e) => Mission.fromJson(e))
            .toList(),
        transactions: (json['transactions'] as List? ?? [])
            .map((e) => Transaction.fromJson(e))
            .toList(),
        badges: (json['badges'] as List? ?? [])
            .map((e) => Badge.fromJson(e))
            .toList(),
        gifted: json['gifted'] ?? 0,
      );
}