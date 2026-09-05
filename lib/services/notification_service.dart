import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/food_item.dart';

class NotificationService {
  static const _channel = MethodChannel('tabekiri/notifications');

  bool _initialized = false;
  Future<void> _syncTail = Future<void>.value();

  bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
  }) {
    if (!isSupported || !_initialized) return Future<void>.value();

    final now = DateTime.now();
    final reminders = <Map<String, Object>>[];

    for (final item in items.where((item) => !item.isConsumed)) {
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

    reminders.sort(
      (a, b) => (a['scheduledAt']! as int).compareTo(b['scheduledAt']! as int),
    );

    final arguments = <String, Object>{
      'enabled': enabled,
      // iOS keeps at most 64 pending local notifications per app.
      'reminders': reminders.take(64).toList(),
    };

    // 全置換の同期が重なって、古い予約が最後に残ることを防ぐ。
    final operation = _syncTail.then((_) => _sendReminders(arguments));
    _syncTail = operation;
    return operation;
  }

  Future<void> _sendReminders(Map<String, Object> arguments) async {
    try {
      await _channel.invokeMethod<void>('syncReminders', arguments);
    } catch (_) {
      // 通知の失敗で食品登録や食べきり操作を止めない。
    }
  }
}
