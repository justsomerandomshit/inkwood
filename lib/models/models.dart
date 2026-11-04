import 'package:flutter/material.dart';

/// The kinds of timer the app offers. [manual] marks words logged by hand.
enum TimerKind {
  pomodoro('Pomodoro', Icons.timer_outlined),
  deepFocus('Deep focus', Icons.self_improvement),
  sprint('Sprint', Icons.bolt_outlined),
  countdown('Countdown', Icons.hourglass_bottom),
  stopwatch('Free write', Icons.all_inclusive),
  manual('Logged', Icons.edit_note);

  const TimerKind(this.label, this.icon);
  final String label;
  final IconData icon;

  bool get hasBreaks => this == pomodoro || this == deepFocus;
  bool get countsUp => this == stopwatch;
  bool get adjustableLength => this == sprint || this == countdown;

  static List<TimerKind> get selectable =>
      values.where((k) => k != manual).toList();

  static TimerKind parse(String? s) =>
      values.firstWhere((k) => k.name == s, orElse: () => manual);
}

@immutable
class WritingSession {
  const WritingSession({
    required this.id,
    required this.start,
    required this.durationSec,
    required this.words,
    required this.kind,
    this.note,
  });

  final String id;
  final DateTime start;
  final int durationSec;
  final int words;
  final TimerKind kind;
  final String? note;

  /// Words per hour, or null when the session wasn't timed.
  double? get pace => durationSec >= 60 ? words / (durationSec / 3600) : null;

  WritingSession copyWith({
    DateTime? start,
    int? durationSec,
    int? words,
    String? note,
  }) => WritingSession(
    id: id,
    start: start ?? this.start,
    durationSec: durationSec ?? this.durationSec,
    words: words ?? this.words,
    kind: kind,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'start': start.toIso8601String(),
    'dur': durationSec,
    'words': words,
    'kind': kind.name,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  factory WritingSession.fromJson(Map<String, dynamic> j) => WritingSession(
    id: j['id'] as String,
    start: DateTime.parse(j['start'] as String),
    durationSec: (j['dur'] as num).toInt(),
    words: (j['words'] as num).toInt(),
    kind: TimerKind.parse(j['kind'] as String?),
    note: j['note'] as String?,
  );
}

/// Manual overrides on the heat map.
enum DayMark {
  /// Count the day as goal met (e.g. writing done away from the app).
  done,

  /// A planned rest day — doesn't break the streak.
  rest,
}

@immutable
class GoalEntry {
  const GoalEntry(this.from, this.words);
  final DateTime from;
  final int words;

  Map<String, dynamic> toJson() => {
    'from': from.toIso8601String(),
    'words': words,
  };
  factory GoalEntry.fromJson(Map<String, dynamic> j) => GoalEntry(
    DateTime.parse(j['from'] as String),
    (j['words'] as num).toInt(),
  );
}

class AppSettings {
  int pomodoroFocus = 25;
  int pomodoroShort = 5;
  int pomodoroLong = 15;
  int pomodoroRounds = 4;
  int deepFocus = 50;
  int deepBreak = 10;
  int sprint = 15;
  int countdown = 30;
  bool autoStartBreaks = true;
  bool keepScreenOn = true;
  bool notifications = true;
  bool chime = true;
  ThemeMode themeMode = ThemeMode.system;

  Map<String, dynamic> toJson() => {
    'pomodoroFocus': pomodoroFocus,
    'pomodoroShort': pomodoroShort,
    'pomodoroLong': pomodoroLong,
    'pomodoroRounds': pomodoroRounds,
    'deepFocus': deepFocus,
    'deepBreak': deepBreak,
    'sprint': sprint,
    'countdown': countdown,
    'autoStartBreaks': autoStartBreaks,
    'keepScreenOn': keepScreenOn,
    'notifications': notifications,
    'chime': chime,
    'themeMode': themeMode.name,
  };

  static AppSettings fromJson(Map<String, dynamic>? j) {
    final s = AppSettings();
    if (j == null) return s;
    int i(String k, int d) => (j[k] as num?)?.toInt() ?? d;
    s
      ..pomodoroFocus = i('pomodoroFocus', s.pomodoroFocus)
      ..pomodoroShort = i('pomodoroShort', s.pomodoroShort)
      ..pomodoroLong = i('pomodoroLong', s.pomodoroLong)
      ..pomodoroRounds = i('pomodoroRounds', s.pomodoroRounds)
      ..deepFocus = i('deepFocus', s.deepFocus)
      ..deepBreak = i('deepBreak', s.deepBreak)
      ..sprint = i('sprint', s.sprint)
      ..countdown = i('countdown', s.countdown)
      ..autoStartBreaks = j['autoStartBreaks'] as bool? ?? s.autoStartBreaks
      ..keepScreenOn = j['keepScreenOn'] as bool? ?? s.keepScreenOn
      ..notifications = j['notifications'] as bool? ?? s.notifications
      ..chime = j['chime'] as bool? ?? s.chime
      ..themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == j['themeMode'],
        orElse: () => ThemeMode.system,
      );
    return s;
  }
}
