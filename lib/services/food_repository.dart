import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/food_item.dart';

class FoodRepository {
  FoodRepository();

  static const _itemsKey = 'tabekiri_food_items_v1';
  static const _pointsKey = 'tabekiri_points_v1';
  static const _notificationsKey = 'tabekiri_notifications_v1';
  static const _reminderHourKey = 'tabekiri_reminder_hour_v1';

  Future<AppSnapshot> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawItems = preferences.getString(_itemsKey);
    final points = preferences.getInt(_pointsKey);

    if (rawItems == null) {
      return AppSnapshot(
        items: _sampleItems(),
        points: points ?? 120,
        notificationsEnabled: preferences.getBool(_notificationsKey) ?? false,
        reminderHour: preferences.getInt(_reminderHourKey) ?? 9,
      );
    }

    try {
      final decoded = jsonDecode(rawItems) as List<dynamic>;
      return AppSnapshot(
        items: decoded
            .map((item) => FoodItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        points: points ?? 0,
        notificationsEnabled: preferences.getBool(_notificationsKey) ?? false,
        reminderHour: preferences.getInt(_reminderHourKey) ?? 9,
      );
    } catch (_) {
      return AppSnapshot(
        items: _sampleItems(),
        points: points ?? 120,
        notificationsEnabled: preferences.getBool(_notificationsKey) ?? false,
        reminderHour: preferences.getInt(_reminderHourKey) ?? 9,
      );
    }
  }

  Future<void> save(AppSnapshot snapshot) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(
        _itemsKey,
        jsonEncode(snapshot.items.map((item) => item.toJson()).toList()),
      ),
      preferences.setInt(_pointsKey, snapshot.points),
      preferences.setBool(_notificationsKey, snapshot.notificationsEnabled),
      preferences.setInt(_reminderHourKey, snapshot.reminderHour),
    ]);
  }

  List<FoodItem> _sampleItems() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [
      FoodItem(
        id: 'sample-yogurt',
        name: 'プレーンヨーグルト',
        category: '乳製品',
        expiryDate: today.add(const Duration(days: 1)),
        registeredAt: now,
        registeredWithAi: true,
      ),
      FoodItem(
        id: 'sample-milk',
        name: '牛乳',
        category: '飲み物',
        expiryDate: today.add(const Duration(days: 3)),
        registeredAt: now,
        registeredWithAi: false,
      ),
      FoodItem(
        id: 'sample-tofu',
        name: '絹ごし豆腐',
        category: '冷蔵品',
        expiryDate: today.add(const Duration(days: 6)),
        registeredAt: now,
        registeredWithAi: true,
      ),
    ];
  }
}
