class FoodItem {
  const FoodItem({
    required this.id,
    required this.name,
    required this.category,
    required this.expiryDate,
    required this.registeredAt,
    required this.registeredWithAi,
    this.consumedAt,
    this.earnedPoints = 0,
  });

  final String id;
  final String name;
  final String category;
  final DateTime expiryDate;
  final DateTime registeredAt;
  final bool registeredWithAi;
  final DateTime? consumedAt;
  final int earnedPoints;

  bool get isConsumed => consumedAt != null;

  int get daysRemaining {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.difference(today).inDays;
  }

  FoodItem consume({required int points}) => FoodItem(
    id: id,
    name: name,
    category: category,
    expiryDate: expiryDate,
    registeredAt: registeredAt,
    registeredWithAi: registeredWithAi,
    consumedAt: DateTime.now(),
    earnedPoints: points,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'expiryDate': expiryDate.toIso8601String(),
    'registeredAt': registeredAt.toIso8601String(),
    'registeredWithAi': registeredWithAi,
    'consumedAt': consumedAt?.toIso8601String(),
    'earnedPoints': earnedPoints,
  };

  factory FoodItem.fromJson(Map<String, dynamic> json) => FoodItem(
    id: json['id'] as String,
    name: json['name'] as String,
    category: json['category'] as String? ?? 'その他',
    expiryDate: DateTime.parse(json['expiryDate'] as String),
    registeredAt: DateTime.parse(json['registeredAt'] as String),
    registeredWithAi: json['registeredWithAi'] as bool? ?? false,
    consumedAt: json['consumedAt'] == null
        ? null
        : DateTime.parse(json['consumedAt'] as String),
    earnedPoints: json['earnedPoints'] as int? ?? 0,
  );
}

class AppSnapshot {
  const AppSnapshot({
    required this.items,
    required this.points,
    this.notificationsEnabled = false,
    this.reminderHour = 9,
  });

  final List<FoodItem> items;
  final int points;
  final bool notificationsEnabled;
  final int reminderHour;
}
