import 'package:flutter_test/flutter_test.dart';
import 'package:inkwood/data/notifier.dart';
import 'package:inkwood/data/timer_controller.dart';
import 'package:inkwood/data/writing_store.dart';
import 'package:inkwood/models/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records what the timer asked the notification layer to do.
class FakeNotifier extends TimerNotifier {
  final calls = <String>[];
  TimerNotice? last;
  bool? lastSound;

  @override
  Future<void> requestPermission() async => calls.add('permission');

  @override
  Future<void> running(TimerNotice n, {required bool sound}) async {
    calls.add('running');
    last = n;
    lastSound = sound;
  }

  @override
  Future<void> paused(String title, Duration left) async => calls.add('paused');

  @override
  Future<void> finished() async => calls.add('finished');

  @override
  Future<void> stopped() async => calls.add('stopped');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late FakeNotifier notes;
  late TimerController timer;
  late WritingStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    now = DateTime(2026, 11, 4, 9);
    store = WritingStore(prefs, clock: () => now);
    notes = FakeNotifier();
    timer = TimerController(store, prefs, clock: () => now, notifier: notes);
  });

  tearDown(() => timer.dispose());

  test('start schedules the end, with permission asked once', () async {
    timer.start();
    await pumpEventQueue();
    expect(notes.calls, ['permission', 'running']);
    expect(notes.last!.anchor, now.add(const Duration(minutes: 25)));
    expect(notes.last!.title, 'Focus · Pomodoro');
    expect(notes.lastSound, isTrue);

    timer.pause();
    timer.start();
    await pumpEventQueue();
    expect(notes.calls, ['permission', 'running', 'paused', 'running']);
  });

  test('reset clears notifications', () async {
    timer.start();
    timer.reset();
    await pumpEventQueue();
    expect(notes.calls.last, 'stopped');
  });

  test('completion clears the countdown and moves to a break', () async {
    timer.start();
    now = now.add(const Duration(minutes: 25, seconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(notes.calls, contains('finished'));
    expect(timer.phase, TimerPhase.shortBreak);
    expect(timer.pendingLog?.seconds, 25 * 60);
  });

  test('settings turn notifications and the chime off', () async {
    store.updateSettings((s) => s.chime = false);
    timer.start();
    await pumpEventQueue();
    expect(notes.lastSound, isFalse);

    timer.reset();
    store.updateSettings((s) => s.notifications = false);
    await pumpEventQueue();
    notes.calls.clear();
    timer.start();
    await pumpEventQueue();
    expect(notes.calls, ['stopped']);
  });

  test('changing a length in settings updates the clock', () {
    var redraws = 0;
    timer.addListener(() => redraws++);
    store.updateSettings((s) => s.pomodoroFocus = 1);
    expect(redraws, greaterThan(0));
    expect(timer.display, const Duration(minutes: 1));
  });

  test('stopwatch counts up from its start time', () async {
    timer.selectKind(TimerKind.stopwatch);
    timer.start();
    await pumpEventQueue();
    expect(notes.last!.countsUp, isTrue);
    expect(notes.last!.anchor, now);
  });
}
