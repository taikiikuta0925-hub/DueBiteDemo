import 'package:flutter_application_1/services/food_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('新規ユーザーは0ポイントから始まる', () async {
    final snapshot = await FoodRepository().load();

    expect(snapshot.points, 0);
  });

  test('保存済みのポイントは保持する', () async {
    SharedPreferences.setMockInitialValues({'tabekiri_points_v1': 240});

    final snapshot = await FoodRepository().load();

    expect(snapshot.points, 240);
  });

  test('食品データが壊れていても未保存なら0ポイントに戻る', () async {
    SharedPreferences.setMockInitialValues({
      'tabekiri_food_items_v1': 'not-json',
    });

    final snapshot = await FoodRepository().load();

    expect(snapshot.points, 0);
  });
}
