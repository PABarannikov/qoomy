class PlayerStats {
  final int questionsAsHost;
  final int questionsAsPlayer;
  final int wrongAnswers;
  final int correctAnswersFirst;
  final int correctAnswersNotFirst;
  final double totalPoints;

  PlayerStats({
    this.questionsAsHost = 0,
    this.questionsAsPlayer = 0,
    this.wrongAnswers = 0,
    this.correctAnswersFirst = 0,
    this.correctAnswersNotFirst = 0,
    this.totalPoints = 0.0,
  });

  int get correctAnswersTotal => correctAnswersFirst + correctAnswersNotFirst;

  PlayerStats copyWith({
    int? questionsAsHost,
    int? questionsAsPlayer,
    int? wrongAnswers,
    int? correctAnswersFirst,
    int? correctAnswersNotFirst,
    double? totalPoints,
  }) {
    return PlayerStats(
      questionsAsHost: questionsAsHost ?? this.questionsAsHost,
      questionsAsPlayer: questionsAsPlayer ?? this.questionsAsPlayer,
      wrongAnswers: wrongAnswers ?? this.wrongAnswers,
      correctAnswersFirst: correctAnswersFirst ?? this.correctAnswersFirst,
      correctAnswersNotFirst: correctAnswersNotFirst ?? this.correctAnswersNotFirst,
      totalPoints: totalPoints ?? this.totalPoints,
    );
  }
}
