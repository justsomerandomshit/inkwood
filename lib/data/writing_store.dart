import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../util/format.dart';

/// A restorable copy of the store's user data (used for undo and backups).
class StoreSnapshot {
  StoreSnapshot(this.json);
  final Map<String, dynamic> json;
}

/// Single source of truth for sessions, goals, heat-map marks and settings.
/// Persisted as one JSON document in SharedPreferences.
class WritingStore extends ChangeNotifier {
  WritingStore(this._prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _load();
  }

  static const _key = 'inkwood.state.v1';
  static const defaultGoal = 500;

  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  final List<WritingSession> _sessions = [];
  List<GoalEntry> _goals = [GoalEntry(DateTime(2000), defaultGoal)];
  final Map<String, DayMark> _marks = {};
  DateTime? _freshStart;
  int? lastManuscriptTotal;
  AppSettings settings = AppSettings();

  Map<String, int>? _wordsByDay;
  Map<String, int>? _secondsByDay;

  // ---------------------------------------------------------------- reads

  DateTime get today => dayOf(_clock());
  List<WritingSession> get sessions => List.unmodifiable(_sessions);
  bool get isEmpty => _sessions.isEmpty && _marks.isEmpty;
  DateTime? get freshStart => _freshStart;
  int get currentGoal => goalFor(today);
  int get totalWords => _sessions.fold(0, (a, s) => a + s.words);
  int get totalSeconds => _sessions.fold(0, (a, s) => a + s.durationSec);

  DateTime? get firstDay {
    final days = [
      if (_sessions.isNotEmpty) dayOf(_sessions.first.start),
      ..._marks.keys.map(parseDayKey),
    ];
    if (days.isEmpty) return null;
    return days.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  int goalFor(DateTime day) {
    var goal = _goals.first.words;
    for (final g in _goals) {
      if (!g.from.isAfter(day)) goal = g.words;
    }
    return goal;
  }

  void _index() {
    if (_wordsByDay != null) return;
    final w = <String, int>{};
    final s = <String, int>{};
    for (final x in _sessions) {
      final k = dayKey(x.start);
      w[k] = (w[k] ?? 0) + x.words;
      s[k] = (s[k] ?? 0) + x.durationSec;
    }
    _wordsByDay = w;
    _secondsByDay = s;
  }

  int wordsOn(DateTime day) {
    _index();
    return _wordsByDay![dayKey(day)] ?? 0;
  }

  int secondsOn(DateTime day) {
    _index();
    return _secondsByDay![dayKey(day)] ?? 0;
  }

  DayMark? markOn(DateTime day) => _marks[dayKey(day)];

  List<WritingSession> sessionsOn(DateTime day) =>
      _sessions.where((s) => sameDay(s.start, day)).toList();

  bool goalMetOn(DateTime day) =>
      markOn(day) == DayMark.done || wordsOn(day) >= goalFor(day);

  /// A day that keeps the streak alive: any words, or marked done.
  bool _countsForStreak(DateTime day) =>
      wordsOn(day) > 0 || markOn(day) == DayMark.done;

  bool isBeforeFreshStart(DateTime day) =>
      _freshStart != null && day.isBefore(_freshStart!);

  /// Consecutive writing days ending today (or yesterday, if today hasn't
  /// been written yet). Rest days are skipped without breaking the chain.
  int get currentStreak {
    final floor = _streakFloor;
    if (floor == null) return 0;
    var d = today;
    if (!_countsForStreak(d)) d = addDays(d, -1);
    var streak = 0;
    while (!d.isBefore(floor)) {
      if (_countsForStreak(d)) {
        streak++;
      } else if (markOn(d) != DayMark.rest) {
        break;
      }
      d = addDays(d, -1);
    }
    return streak;
  }

  int get bestStreak {
    final floor = _streakFloor;
    if (floor == null) return 0;
    var best = 0, run = 0;
    for (var d = floor; !d.isAfter(today); d = addDays(d, 1)) {
      if (_countsForStreak(d)) {
        run++;
        best = max(best, run);
      } else if (markOn(d) != DayMark.rest && !sameDay(d, today)) {
        run = 0;
      }
    }
    return best;
  }

  DateTime? get _streakFloor {
    final first = firstDay;
    if (first == null) return null;
    if (_freshStart != null && _freshStart!.isAfter(first)) return _freshStart;
    return first;
  }

  // --------------------------------------------------------------- writes

  String _newId() =>
      '${_clock().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';

  WritingSession addSession({
    required DateTime start,
    required int durationSec,
    required int words,
    required TimerKind kind,
    String? note,
  }) {
    final s = WritingSession(
      id: _newId(),
      start: start,
      durationSec: max(0, durationSec),
      words: max(0, words),
      kind: kind,
      note: note,
    );
    insertSession(s);
    return s;
  }

  /// Inserts (or re-inserts, for undo) a session keeping chronological order.
  void insertSession(WritingSession s) {
    final i = _sessions.indexWhere((x) => x.start.isAfter(s.start));
    _sessions.insert(i < 0 ? _sessions.length : i, s);
    _changed();
  }

  void updateSession(WritingSession s) {
    final i = _sessions.indexWhere((x) => x.id == s.id);
    if (i < 0) return;
    _sessions.removeAt(i);
    insertSession(s);
  }

  void removeSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    _changed();
  }

  /// Sets the daily goal from today onward; earlier days keep their goal.
  void setGoal(int words) {
    final t = today;
    _goals = [
      ..._goals.where((g) => g.from.isBefore(t)),
      GoalEntry(t, max(1, words)),
    ];
    _changed();
  }

  void setMark(DateTime day, DayMark? mark) {
    final k = dayKey(day);
    if (mark == null) {
      _marks.remove(k);
    } else {
      _marks[k] = mark;
    }
    _changed();
  }

  /// Applies [mark] to every past (or current) day in [month] that [where]
  /// accepts. Passing a null mark clears marks.
  void markMonth(
    DateTime month,
    DayMark? mark, {
    bool Function(DateTime day)? where,
  }) {
    for (var d = 1; d <= daysInMonth(month); d++) {
      final day = DateTime(month.year, month.month, d);
      if (day.isAfter(today)) break;
      if (where != null && !where(day)) continue;
      final k = dayKey(day);
      if (mark == null) {
        _marks.remove(k);
      } else {
        _marks[k] = mark;
      }
    }
    _changed();
  }

  void startFresh(DateTime from) {
    _freshStart = dayOf(from);
    _changed();
  }

  void clearFreshStart() {
    _freshStart = null;
    _changed();
  }

  /// Erases sessions and marks inside [month].
  void clearMonth(DateTime month) {
    bool inMonth(DateTime d) => d.year == month.year && d.month == month.month;
    _sessions.removeWhere((s) => inMonth(s.start));
    _marks.removeWhere((k, _) => inMonth(parseDayKey(k)));
    _changed();
  }

  void setManuscriptTotal(int? total) {
    lastManuscriptTotal = total;
    _save();
  }

  void updateSettings(void Function(AppSettings s) change) {
    change(settings);
    _save();
    notifyListeners();
  }

  void eraseAll() {
    _sessions.clear();
    _marks.clear();
    _freshStart = null;
    lastManuscriptTotal = null;
    _goals = [GoalEntry(DateTime(2000), currentGoal)];
    _changed();
  }

  // ------------------------------------------------------ snapshot / io

  StoreSnapshot snapshot() =>
      StoreSnapshot(jsonDecode(jsonEncode(_toJson())) as Map<String, dynamic>);

  void restore(StoreSnapshot s) {
    _fromJson(s.json);
    _changed();
  }

  String exportJson() => const JsonEncoder.withIndent('  ').convert(_toJson());

  /// Throws [FormatException] if the text isn't an Inkwood backup.
  void importJson(String text) {
    final data = jsonDecode(text);
    if (data is! Map<String, dynamic> || data['app'] != 'inkwood') {
      throw const FormatException('Not an Inkwood backup');
    }
    _fromJson(data);
    _changed();
  }

  /// Fills the last ~10 weeks with plausible sessions so the charts can be
  /// explored before real data exists.
  void loadSampleData() {
    final rnd = Random(7);
    final kinds = [
      TimerKind.pomodoro,
      TimerKind.pomodoro,
      TimerKind.sprint,
      TimerKind.deepFocus,
      TimerKind.stopwatch,
    ];
    for (var back = 70; back >= 0; back--) {
      final day = addDays(today, -back);
      if (rnd.nextDouble() < 0.22) continue;
      final count = 1 + rnd.nextInt(3);
      for (var i = 0; i < count; i++) {
        final kind = kinds[rnd.nextInt(kinds.length)];
        final minutes = switch (kind) {
          TimerKind.pomodoro => 25,
          TimerKind.deepFocus => 50,
          TimerKind.sprint => 15,
          _ => 20 + rnd.nextInt(50),
        };
        final pace = switch (kind) {
          TimerKind.sprint => 1300 + rnd.nextInt(500),
          TimerKind.deepFocus => 750 + rnd.nextInt(400),
          _ => 850 + rnd.nextInt(450),
        };
        final hour = rnd.nextDouble() < 0.6
            ? 19 + rnd.nextInt(4)
            : 7 + rnd.nextInt(6);
        final start = DateTime(
          day.year,
          day.month,
          day.day,
          hour,
          rnd.nextInt(60),
        );
        if (start.isAfter(_clock())) continue;
        _sessions.add(
          WritingSession(
            id: _newId() + i.toString(),
            start: start,
            durationSec: minutes * 60,
            words: (pace * minutes / 60).round(),
            kind: kind,
          ),
        );
      }
    }
    _sessions.sort((a, b) => a.start.compareTo(b.start));
    _changed();
  }

  Map<String, dynamic> _toJson() => {
    'app': 'inkwood',
    'version': 1,
    'sessions': _sessions.map((s) => s.toJson()).toList(),
    'goals': _goals.map((g) => g.toJson()).toList(),
    'marks': _marks.map((k, v) => MapEntry(k, v.name)),
    'freshStart': _freshStart?.toIso8601String(),
    'manuscriptTotal': lastManuscriptTotal,
    'settings': settings.toJson(),
  };

  void _fromJson(Map<String, dynamic> j) {
    _sessions
      ..clear()
      ..addAll(
        (j['sessions'] as List? ?? []).map(
          (e) => WritingSession.fromJson(e as Map<String, dynamic>),
        ),
      )
      ..sort((a, b) => a.start.compareTo(b.start));
    final goals = (j['goals'] as List? ?? [])
        .map((e) => GoalEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    _goals = goals.isEmpty ? [GoalEntry(DateTime(2000), defaultGoal)] : goals;
    _marks
      ..clear()
      ..addAll(
        (j['marks'] as Map<String, dynamic>? ?? {}).map(
          (k, v) => MapEntry(k, DayMark.values.byName(v as String)),
        ),
      );
    final fs = j['freshStart'] as String?;
    _freshStart = fs == null ? null : DateTime.parse(fs);
    lastManuscriptTotal = (j['manuscriptTotal'] as num?)?.toInt();
    settings = AppSettings.fromJson(j['settings'] as Map<String, dynamic>?);
    _wordsByDay = null;
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      _fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Inkwood: could not read saved data: $e');
    }
  }

  void _save() => _prefs.setString(_key, jsonEncode(_toJson()));

  void _changed() {
    _wordsByDay = null;
    _secondsByDay = null;
    _save();
    notifyListeners();
  }
}
