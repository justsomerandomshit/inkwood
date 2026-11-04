import 'package:inkwood/data/stats.dart';
import 'package:inkwood/data/writing_store.dart';
import 'package:inkwood/models/models.dart';
import 'package:inkwood/util/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  final now = DateTime(2026, 11, 4, 15);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  WritingStore make() => WritingStore(prefs, clock: () => now);

  void write(WritingStore s, int daysAgo, int words, {int minutes = 25}) {
    final d = addDays(dayOf(now), -daysAgo);
    s.addSession(
      start: DateTime(d.year, d.month, d.day, 9),
      durationSec: minutes * 60,
      words: words,
      kind: TimerKind.pomodoro,
    );
  }

  test('streak counts back from yesterday when today is still empty', () {
    final s = make();
    write(s, 1, 300);
    write(s, 2, 300);
    write(s, 4, 300);
    expect(s.currentStreak, 2);
  });

  test('rest days bridge a streak without counting', () {
    final s = make();
    write(s, 0, 100);
    s.setMark(addDays(dayOf(now), -1), DayMark.rest);
    write(s, 2, 100);
    write(s, 3, 100);
    expect(s.currentStreak, 3);
    expect(s.bestStreak, 3);
  });

  test('fresh start resets the streak floor but keeps history', () {
    final s = make();
    for (var i = 1; i <= 5; i++) {
      write(s, i, 200);
    }
    s.startFresh(dayOf(now));
    expect(s.currentStreak, 0);
    expect(s.sessions.length, 5);
    expect(s.isBeforeFreshStart(addDays(dayOf(now), -1)), isTrue);
  });

  test('goal changes only apply from today', () {
    final s = make();
    s.setGoal(1000);
    expect(s.goalFor(dayOf(now)), 1000);
    expect(s.goalFor(addDays(dayOf(now), -1)), WritingStore.defaultGoal);
  });

  test('done mark meets the goal regardless of words', () {
    final s = make();
    final d = addDays(dayOf(now), -3);
    expect(s.goalMetOn(d), isFalse);
    s.setMark(d, DayMark.done);
    expect(s.goalMetOn(d), isTrue);
  });

  test('state persists and backups round-trip', () {
    final s = make();
    write(s, 0, 640);
    s.setGoal(750);
    final reloaded = make();
    expect(reloaded.totalWords, 640);
    expect(reloaded.currentGoal, 750);

    final backup = s.exportJson();
    s.eraseAll();
    expect(s.totalWords, 0);
    s.importJson(backup);
    expect(s.totalWords, 640);
    expect(() => s.importJson('{"nope":1}'), throwsFormatException);
  });

  test('range stats: totals, median, pace, previous period', () {
    final s = make();
    write(s, 0, 500, minutes: 30); // 1000 w/h
    write(s, 1, 300, minutes: 30);
    write(s, 2, 1000, minutes: 60);
    write(s, 10, 900); // outside the week, inside "previous week"
    final st = computeStats(s, StatsRange.week);
    expect(st.words, 1800);
    expect(st.seconds, 120 * 60);
    expect(st.medianSession, 500);
    expect(st.pace, 900);
    expect(st.previousWords, 900);
    expect(st.buckets.length, 7);
    expect(st.buckets.last.words, 500);
    expect(st.writingDays, 3);
    expect(st.avgOnWritingDays, 600);
    expect(st.cumulative.last, 1800);
  });

  test('year view buckets by month', () {
    final s = make();
    write(s, 0, 100);
    write(s, 40, 200);
    final st = computeStats(s, StatsRange.year);
    expect(st.daily, isFalse);
    expect(st.buckets.length, 12);
    expect(st.buckets.last.words, 100);
  });

  test('niceCeil picks readable axis maxima', () {
    expect(niceCeil(0), 100);
    expect(niceCeil(87), 100);
    expect(niceCeil(1100), 1500);
    expect(niceCeil(2300), 2500);
    expect(niceCeil(2600), 3000);
    expect(niceCeil(4100), 5000);
  });

  test('formatting', () {
    expect(fmtDuration(42 * 60), '42m');
    expect(fmtDuration(200 * 60), '3h 20m');
    expect(fmtClock(const Duration(minutes: 24, seconds: 5)), '24:05');
    expect(fmtCompact(1240), '1,240');
    expect(fmtCompact(12400), '12.4K');
  });
}
