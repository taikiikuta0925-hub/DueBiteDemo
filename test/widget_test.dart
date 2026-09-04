import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_application_1/main.dart';
import 'package:flutter_application_1/models/food_item.dart';
import 'package:flutter_application_1/services/food_repository.dart';
import 'package:flutter_application_1/services/notification_service.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ホームに期限とポイントが表示される', (tester) async {
    final now = DateTime.now();
    final item = FoodItem(
      id: 'milk',
      name: 'テスト牛乳',
      category: '飲み物',
      expiryDate: DateTime(now.year, now.month, now.day + 1),
      registeredAt: now,
      registeredWithAi: false,
    );

    await tester.pumpWidget(
      DueBiteApp(
        repository: FoodRepository(),
        notificationService: NotificationService(),
        initialSnapshot: AppSnapshot(items: [item], points: 120),
      ),
    );

    expect(find.text('DueBite'), findsOneWidget);
    expect(find.text('テスト牛乳'), findsOneWidget);
    expect(find.text('120 P'), findsOneWidget);
    expect(find.text('あと1日'), findsOneWidget);
  });

  testWidgets('手入力で食品を登録できる', (tester) async {
    await tester.pumpWidget(
      DueBiteApp(
        repository: FoodRepository(),
        notificationService: NotificationService(),
        initialSnapshot: const AppSnapshot(items: [], points: 0),
      ),
    );

    await tester.tap(find.byKey(const Key('add-food-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手入力で登録'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('food-name-field')), 'テスト納豆');
    await tester.tap(find.byKey(const Key('save-food-button')));
    await tester.pumpAndSettle();

    expect(find.text('食品リスト'), findsOneWidget);
    expect(find.text('テスト納豆'), findsOneWidget);
  });

  testWidgets('AIとの会話から商品を特定して登録できる', (tester) async {
    await tester.pumpWidget(
      DueBiteApp(
        repository: FoodRepository(),
        notificationService: NotificationService(),
        initialSnapshot: const AppSnapshot(items: [], points: 0),
      ),
    );

    await tester.tap(find.byKey(const Key('add-food-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AIと会話して登録'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('agent-message-field')),
      '牛乳です。賞味期限は2026年9月10日です',
    );
    await tester.tap(find.byKey(const Key('agent-send-button')));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.text('商品を特定しました'), findsOneWidget);
    await tester.tap(find.text('この内容で登録'));
    await tester.pumpAndSettle();

    expect(find.text('食品リスト'), findsOneWidget);
    expect(find.text('牛乳'), findsWidgets);
  });

  testWidgets('期限内に食べきるとポイントが増える', (tester) async {
    final now = DateTime.now();
    final item = FoodItem(
      id: 'yogurt',
      name: 'テストヨーグルト',
      category: '乳製品',
      expiryDate: DateTime(now.year, now.month, now.day + 1),
      registeredAt: now,
      registeredWithAi: true,
    );
    await tester.pumpWidget(
      DueBiteApp(
        repository: FoodRepository(),
        notificationService: NotificationService(),
        initialSnapshot: AppSnapshot(items: [item], points: 0),
      ),
    );

    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('食べきった'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('食べきった！'));
    await tester.pumpAndSettle();

    expect(find.text('+20 ポイント'), findsOneWidget);
    expect(find.text('合計 20 P'), findsOneWidget);
  });
}
