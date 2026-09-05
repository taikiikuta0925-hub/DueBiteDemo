import 'package:flutter_application_1/models/player_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PlayerLevel', () {
    test('0ポイントからレベル1のたねとして始まる', () {
      final level = PlayerLevel.fromPoints(0);

      expect(level.points, 0);
      expect(level.level, 1);
      expect(level.name, 'たね');
      expect(level.levelStartPoints, 0);
      expect(level.nextLevelPoints, 100);
      expect(level.pointsToNextLevel, 100);
      expect(level.progress, 0);
      expect(level.isMaxLevel, isFalse);
    });

    test('各しきい値で次のレベルへ上がる', () {
      final cases = <int, (int, String)>{
        99: (1, 'たね'),
        100: (2, 'めばえ'),
        299: (2, 'めばえ'),
        300: (3, '若葉'),
        599: (3, '若葉'),
        600: (4, '花'),
        999: (4, '花'),
        1000: (5, '実り'),
      };

      for (final MapEntry(key: points, value: expected) in cases.entries) {
        final level = PlayerLevel.fromPoints(points);

        expect(level.level, expected.$1, reason: '$points P');
        expect(level.name, expected.$2, reason: '$points P');
      }
    });

    test('レベル内の進捗と次のレベルまでのポイントを返す', () {
      final level = PlayerLevel.fromPoints(200);

      expect(level.level, 2);
      expect(level.levelStartPoints, 100);
      expect(level.nextLevelPoints, 300);
      expect(level.pointsToNextLevel, 100);
      expect(level.progress, 0.5);
    });

    test('最高レベルでは進捗を完了状態にする', () {
      final level = PlayerLevel.fromPoints(1250);

      expect(level.level, 5);
      expect(level.name, '実り');
      expect(level.nextLevelPoints, isNull);
      expect(level.pointsToNextLevel, 0);
      expect(level.progress, 1);
      expect(level.isMaxLevel, isTrue);
    });

    test('負のポイントは0として扱う', () {
      final level = PlayerLevel.fromPoints(-10);

      expect(level.points, 0);
      expect(level.level, 1);
      expect(level.progress, 0);
      expect(level.pointsToNextLevel, 100);
    });
  });
}
