import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_application_1/models/food_item.dart';
import 'package:flutter_application_1/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('tabekiri/notifications');
  late List<MethodCall> calls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize' ||
              call.method == 'requestPermission') {
            return true;
          }
          return null;
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('iOSで3日前と当日の通知を時刻順に同期する', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiredItems = List.generate(
      40,
      (index) => FoodItem(
        id: 'expired-$index',
        name: '期限切れ$index',
        category: 'その他',
        expiryDate: today.subtract(Duration(days: index + 1)),
        registeredAt: now,
        registeredWithAi: false,
      ),
    );
    final upcoming = FoodItem(
      id: 'upcoming',
      name: '牛乳',
      category: '飲み物',
      expiryDate: today.add(const Duration(days: 5)),
      registeredAt: now,
      registeredWithAi: false,
    );
    final consumed = FoodItem(
      id: 'consumed',
      name: '食べきり済み',
      category: 'その他',
      expiryDate: today.add(const Duration(days: 2)),
      registeredAt: now,
      registeredWithAi: false,
      consumedAt: now,
    );

    final service = NotificationService();
    expect(service.isSupported, isTrue);
    await service.initialize();
    await service.syncReminders(
      items: [...expiredItems, upcoming, consumed],
      enabled: true,
      reminderHour: 9,
    );

    expect(calls.map((call) => call.method), ['initialize', 'syncReminders']);
    final arguments = calls.last.arguments as Map<Object?, Object?>;
    final reminders = (arguments['reminders']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    expect(arguments['enabled'], isTrue);
    expect(reminders.map((reminder) => reminder['id']), [
      'upcoming-before',
      'upcoming-today',
    ]);
    expect(reminders.first['title'], '賞味期限まであと3日');
    expect(reminders.last['title'], '今日が賞味期限です');
    expect(
      reminders.first['scheduledAt'] as int,
      lessThan(reminders.last['scheduledAt'] as int),
    );
  });

  test('保留通知をiOSの上限64件に収める', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final items = List.generate(
      40,
      (index) => FoodItem(
        id: 'item-$index',
        name: '食品$index',
        category: 'その他',
        expiryDate: today.add(Duration(days: index + 5)),
        registeredAt: now,
        registeredWithAi: false,
      ),
    );

    final service = NotificationService();
    await service.initialize();
    await service.syncReminders(items: items, enabled: true, reminderHour: 9);

    final arguments = calls.last.arguments as Map<Object?, Object?>;
    final reminders = arguments['reminders']! as List<Object?>;
    expect(reminders, hasLength(64));
  });

  test('連続した全置換同期を呼び出し順に処理する', () async {
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final syncedIds = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'initialize') return true;
          if (call.method != 'syncReminders') return null;

          final arguments = call.arguments as Map<Object?, Object?>;
          final reminders = (arguments['reminders']! as List<Object?>)
              .cast<Map<Object?, Object?>>();
          syncedIds.add(reminders.first['itemId']! as String);
          if (syncedIds.length == 1) {
            firstStarted.complete();
            await releaseFirst.future;
          }
          return null;
        });

    final now = DateTime.now();
    final expiryDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: 5));
    FoodItem item(String id) => FoodItem(
      id: id,
      name: id,
      category: 'その他',
      expiryDate: expiryDate,
      registeredAt: now,
      registeredWithAi: false,
    );

    final service = NotificationService();
    await service.initialize();
    final first = service.syncReminders(
      items: [item('first')],
      enabled: true,
      reminderHour: 9,
    );
    await firstStarted.future;
    final second = service.syncReminders(
      items: [item('second')],
      enabled: true,
      reminderHour: 9,
    );
    await Future<void>.delayed(Duration.zero);

    expect(syncedIds, ['first']);
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect(syncedIds, ['first', 'second']);
  });
}
