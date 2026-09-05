class PlayerLevel {
  const PlayerLevel._({
    required this.points,
    required this.level,
    required this.name,
    required this.levelStartPoints,
    required this.nextLevelPoints,
    required this.progress,
    required this.pointsToNextLevel,
  });

  static const List<int> thresholds = [0, 100, 300, 600, 1000];
  static const List<String> names = ['たね', 'めばえ', '若葉', '花', '実り'];

  factory PlayerLevel.fromPoints(int points) {
    final normalizedPoints = points < 0 ? 0 : points;
    var levelIndex = 0;

    for (var index = 1; index < thresholds.length; index++) {
      if (normalizedPoints < thresholds[index]) break;
      levelIndex = index;
    }

    final levelStartPoints = thresholds[levelIndex];
    final nextLevelPoints = levelIndex < thresholds.length - 1
        ? thresholds[levelIndex + 1]
        : null;
    final pointsToNextLevel = nextLevelPoints == null
        ? 0
        : nextLevelPoints - normalizedPoints;
    final progress = nextLevelPoints == null
        ? 1.0
        : (normalizedPoints - levelStartPoints) /
              (nextLevelPoints - levelStartPoints);

    return PlayerLevel._(
      points: normalizedPoints,
      level: levelIndex + 1,
      name: names[levelIndex],
      levelStartPoints: levelStartPoints,
      nextLevelPoints: nextLevelPoints,
      progress: progress,
      pointsToNextLevel: pointsToNextLevel,
    );
  }

  final int points;
  final int level;
  final String name;
  final int levelStartPoints;
  final int? nextLevelPoints;
  final double progress;
  final int pointsToNextLevel;

  bool get isMaxLevel => nextLevelPoints == null;
}
