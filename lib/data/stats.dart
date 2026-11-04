import 'dart:math';

import 'package:intl/intl.dart';

import '../models/models.dart';
import '../util/format.dart';
import 'writing_store.dart';

enum StatsRange {
  week('Week', 'Last 7 days'),
  month('Month', 'Last 30 days'),
  year('Year', 'Last 12 months'),
  all('All', 'All time');

  const StatsRange(this.label, this.caption);
  final String label;
  final String caption;
}

/// One bar on the words chart: a day or a month.
class Bucket {
  Bucket({
    required this.start,
    required this.label,
    required this.words,
    required this.seconds,
    this.goal,
  });
  final DateTime start;
  final String label;
  final int words;
  final int seconds;

  /// Only set for daily buckets.
  final int? goal;
  bool get goalMet => goal != null && words >= goal!;
}

class KindStat {
  KindStat(this.kind);
  final TimerKind kind;
  int sessions = 0, words = 0, seconds = 0;
  double get pace => seconds == 0 ? 0 : words / (seconds / 3600);
}

class RangeStats {
  RangeStats._(this.range, this.start, this.end);

  final StatsRange range;
  final DateTime start;
  final DateTime end;

  int words = 0;
  int seconds = 0;
  int entries = 0;
  int writingDays = 0;
  int? previousWords;

  /// Words ÷ hours across timed sessions only.
  int? pace;
  int? medianSession;

  late bool daily;
  final buckets = <Bucket>[];
  int goalMetDays = 0;
  int countedDays = 0;

  /// Running totals (x = day index) and the goal "par" line.
  final cumulative = <int>[];
  final par = <int>[];

  final byHour = List<int>.filled(24, 0);
  final byWeekday = List<int>.filled(7, 0); // Mon..Sun
  int distinctSessionDays = 0;
  final kinds = <TimerKind, KindStat>{};

  int get avgOnWritingDays => writingDays == 0 ? 0 : words ~/ writingDays;

  /// Change vs the previous period; null when there's nothing fair to compare.
  double? get change {
    final p = previousWords;
    if (p == null || p < 500) return null;
    return (words - p) / p;
  }

  bool get showRhythm => entries >= 8 && distinctSessionDays >= 4;

  List<KindStat> get comparableKinds {
    final list = kinds.values.where((k) => k.sessions >= 3).toList()
      ..sort((a, b) => b.pace.compareTo(a.pace));
    return list.length >= 2 ? list : const [];
  }

  /// Best two-hour block by words written, e.g. (21, 23).
  (int, int)? get bestHours {
    if (byHour.every((w) => w == 0)) return null;
    var best = 0, bestStart = 0;
    for (var h = 0; h < 24; h++) {
      final w = byHour[h] + byHour[(h + 1) % 24];
      if (w > best) {
        best = w;
        bestStart = h;
      }
    }
    return (bestStart, (bestStart + 2) % 24);
  }

  int? get bestWeekday {
    if (byWeekday.every((w) => w == 0)) return null;
    var best = 0;
    for (var i = 1; i < 7; i++) {
      if (byWeekday[i] > byWeekday[best]) best = i;
    }
    return best;
  }
}

class PersonalBests {
  (DateTime, int)? bestDay;
  (DateTime, int)? bestWeek;
  int longestStreak = 0;
  WritingSession? longestSession;
  WritingSession? fastestSession;
}

(DateTime, DateTime) _window(StatsRange r, WritingStore store) {
  final end = store.today;
  switch (r) {
    case StatsRange.week:
      return (addDays(end, -6), end);
    case StatsRange.month:
      return (addDays(end, -29), end);
    case StatsRange.year:
      return (DateTime(end.year, end.month - 11, 1), end);
    case StatsRange.all:
      final first = store.firstDay ?? end;
      return (DateTime(first.year, first.month, 1), end);
  }
}

RangeStats computeStats(WritingStore store, StatsRange range) {
  final (start, end) = _window(range, store);
  final st = RangeStats._(range, start, end);
  final endExclusive = addDays(end, 1);
  bool inWindow(DateTime t) => !t.isBefore(start) && t.isBefore(endExclusive);

  final inRange = store.sessions.where((s) => inWindow(s.start)).toList();
  final sessionDays = <String>{};
  var timedWords = 0, timedSeconds = 0;
  final perSession = <int>[];
  for (final s in inRange) {
    st.words += s.words;
    st.seconds += s.durationSec;
    st.entries++;
    perSession.add(s.words);
    sessionDays.add(dayKey(s.start));
    if (s.durationSec >= 60 && s.kind != TimerKind.manual) {
      timedWords += s.words;
      timedSeconds += s.durationSec;
    }
    st.byHour[s.start.hour] += s.words;
    st.byWeekday[s.start.weekday - 1] += s.words;
    if (s.kind != TimerKind.manual && s.durationSec >= 60) {
      final k = st.kinds.putIfAbsent(s.kind, () => KindStat(s.kind));
      k.sessions++;
      k.words += s.words;
      k.seconds += s.durationSec;
    }
  }
  st.distinctSessionDays = sessionDays.length;
  if (timedSeconds >= 60) {
    st.pace = (timedWords / (timedSeconds / 3600)).round();
  }
  if (perSession.isNotEmpty) {
    perSession.sort();
    final m = perSession.length ~/ 2;
    st.medianSession = perSession.length.isOdd
        ? perSession[m]
        : ((perSession[m - 1] + perSession[m]) / 2).round();
  }

  // Previous period of equal length, for a fair "vs last" comparison.
  if (range != StatsRange.all) {
    final len = daysBetween(start, end) + 1;
    final pStart = addDays(start, -len);
    st.previousWords = store.sessions
        .where((s) => !s.start.isBefore(pStart) && s.start.isBefore(start))
        .fold<int>(0, (a, s) => a + s.words);
  }

  // Daily walk for buckets, goal hits, cumulative and par lines.
  var running = 0, parRunning = 0;
  for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
    final w = store.wordsOn(d);
    final goal = store.goalFor(d);
    if (w > 0) st.writingDays++;
    if (!store.isBeforeFreshStart(d)) {
      st.countedDays++;
      if (store.goalMetOn(d)) st.goalMetDays++;
    }
    running += w;
    parRunning += goal;
    st.cumulative.add(running);
    st.par.add(parRunning);
  }

  st.daily = range == StatsRange.week || range == StatsRange.month;
  if (st.daily) {
    final weekdayFmt = DateFormat.E();
    for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
      st.buckets.add(
        Bucket(
          start: d,
          label: range == StatsRange.week
              ? weekdayFmt.format(d).substring(0, 1)
              : '${d.day}',
          words: store.wordsOn(d),
          seconds: store.secondsOn(d),
          goal: store.goalFor(d),
        ),
      );
    }
  } else {
    final months = <DateTime>[];
    for (
      var m = DateTime(start.year, start.month);
      !m.isAfter(end);
      m = DateTime(m.year, m.month + 1)
    ) {
      months.add(m);
    }
    final yearly = months.length > 24;
    final groups = <DateTime, List<int>>{};
    for (final m in months) {
      final key = yearly ? DateTime(m.year) : m;
      groups.putIfAbsent(key, () => [0, 0]);
    }
    for (final s in inRange) {
      final key = yearly
          ? DateTime(s.start.year)
          : DateTime(s.start.year, s.start.month);
      final g = groups[key];
      if (g == null) continue;
      g[0] += s.words;
      g[1] += s.durationSec;
    }
    final monthFmt = DateFormat.MMM();
    groups.forEach((k, v) {
      st.buckets.add(
        Bucket(
          start: k,
          label: yearly ? '${k.year}' : monthFmt.format(k),
          words: v[0],
          seconds: v[1],
        ),
      );
    });
  }
  return st;
}

PersonalBests computeBests(WritingStore store) {
  final pb = PersonalBests();
  final sessions = store.sessions;
  if (sessions.isEmpty) return pb;
  final byDay = <String, int>{};
  final byWeek = <String, int>{};
  final weekStart = <String, DateTime>{};
  for (final s in sessions) {
    byDay[dayKey(s.start)] = (byDay[dayKey(s.start)] ?? 0) + s.words;
    final monday = addDays(dayOf(s.start), -(s.start.weekday - 1));
    final wk = dayKey(monday);
    byWeek[wk] = (byWeek[wk] ?? 0) + s.words;
    weekStart[wk] = monday;
    if (s.kind != TimerKind.manual &&
        (pb.longestSession == null ||
            s.durationSec > pb.longestSession!.durationSec)) {
      pb.longestSession = s;
    }
    if (s.durationSec >= 600 &&
        (pb.fastestSession == null ||
            (s.pace ?? 0) > (pb.fastestSession!.pace ?? 0))) {
      pb.fastestSession = s;
    }
  }
  final bd = byDay.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (bd.value > 0) pb.bestDay = (parseDayKey(bd.key), bd.value);
  final bw = byWeek.entries.reduce((a, b) => b.value > a.value ? b : a);
  if (bw.value > 0) pb.bestWeek = (weekStart[bw.key]!, bw.value);
  pb.longestStreak = store.bestStreak;
  return pb;
}

/// Projection for the current calendar month, e.g. "~31k by Nov 30".
({int projected, DateTime monthEnd})? monthProjection(WritingStore store) {
  final t = store.today;
  final first = DateTime(t.year, t.month, 1);
  var sum = 0;
  for (var d = first; !d.isAfter(t); d = addDays(d, 1)) {
    sum += store.wordsOn(d);
  }
  if (sum == 0) return null;
  final elapsed = t.day;
  final total = daysInMonth(t);
  return (
    projected: (sum / elapsed * total).round(),
    monthEnd: DateTime(t.year, t.month, total),
  );
}

int maxOf(Iterable<int> xs) => xs.isEmpty ? 0 : xs.reduce(max);
