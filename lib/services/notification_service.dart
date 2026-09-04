import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/food_item.dart';

class NotificationService {
  static const _channel = MethodChannel('tabekiri/notifications');

  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      _initialized = await _channel.invokeMethod<bool>('initialize') ?? false;
    } catch (_) {
      _initialized = false;
    }
  }

  Future<bool> requestPermission() async {
    if (!isSupported || !_initialized) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> syncReminders({
    required List<FoodItem> items,
    required bool enabled,
    required int reminderHour,
  }) async {
    if (!isSupported || !_initialized) return;

    final activeItems = items.where((item) => !item.isConsumed).toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    final now = DateTime.now();
    final reminders = <Map<String, Object>>[];

    for (final item in activeItems.take(32)) {
      final threeDaysBefore = DateTime(
        item.expiryDate.year,
        item.expiryDate.month,
        item.expiryDate.day - 3,
        reminderHour,
      );
      final expiryDay = DateTime(
        item.expiryDate.year,
        item.expiryDate.month,
        item.expiryDate.day,
        reminderHour,
      );
      if (threeDaysBefore.isAfter(now)) {
        reminders.add({
          'id': '${item.id}-before',
          'title': '賞味期限まであと3日',
          'body': '${item.name}をそろそろ食べきりましょう',
          'scheduledAt': threeDaysBefore.millisecondsSinceEpoch,
          'itemId': item.id,
        });
      }
      if (expiryDay.isAfter(now)) {
        reminders.add({
          'id': '${item.id}-today',
          'title': '今日が賞味期限です',
          'body': '${item.name}を忘れずにチェックしましょう',
          'scheduledAt': expiryDay.millisecondsSinceEpoch,
          'itemId': item.id,
        });
      }
    }

    try {
      await _channel.invokeMethod<void>('syncReminders', {
        'enabled': enabled,
        'reminders': reminders,
      });
    } catch (_) {
      // 通知の失敗で食品登録や食べきり操作を止めない。
    }
  }
}
