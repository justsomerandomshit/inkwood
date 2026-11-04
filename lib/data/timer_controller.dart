import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/models.dart';
import 'notifier.dart';
import 'writing_store.dart';

enum TimerPhase {
  focus('Focus'),
  shortBreak('Short break'),
  longBreak('Long break');

  const TimerPhase(this.label);
  final String label;
  bool get isBreak => this != focus;
}

enum TimerStatus { idle, running, paused }

/// A finished stretch of focus waiting for the writer to log their words.
class PendingLog {
  PendingLog({
    required this.start,
    required this.seconds,
    required this.kind,
    required this.completed,
  });
  final DateTime start;
  final int seconds;
  final TimerKind kind;

  /// True when the countdown ran out; false when the writer stopped early.
  final bool completed;
}

/// Drives every timer mode. Time is measured against the wall clock
/// (not tick counts) so it stays exact when the app is backgrounded, and the
/// state is persisted so a running timer survives the process being killed.
class TimerController extends ChangeNotifier with WidgetsBindingObserver {
  TimerController(
    this.store,
    this._prefs, {
    DateTime Function()? clock,
    this.notifier,
  }) : _clock = clock ?? DateTime.now {
    _restore();
    WidgetsBinding.instance.addObserver(this);
    // Timer lengths live in settings: redraw when they change.
    store.addListener(notifyListeners);
  }

  static const _key = 'inkwood.timer.v1';

  final WritingStore store;
  final SharedPreferences _prefs;
  final DateTime Function() _clock;

  /// Android notifications; null in tests.
  final TimerNotifier? notifier;
  bool _askedPermission = false;

  TimerKind kind = TimerKind.pomodoro;
  TimerPhase phase = TimerPhase.focus;
  TimerStatus status = TimerStatus.idle;
  int completedRounds = 0;

  Duration _banked = Duration.zero;
  DateTime? _runningSince;
  DateTime? _focusStartedAt;
  Timer? _ticker;

  PendingLog? pendingLog;

  /// Bumped whenever a phase ends so the UI can play a gentle cue.
  int completions = 0;

  bool get isRunning => status == TimerStatus.running;
  bool get isIdle => status == TimerStatus.idle;

  Duration get elapsed =>
      _banked +
      (_runningSince == null
          ? Duration.zero
          : _clock().difference(_runningSince!));

  /// Null for the count-up stopwatch.
  Duration? get phaseLength {
    final s = store.settings;
    final minutes = switch ((kind, phase)) {
      (TimerKind.stopwatch, _) || (TimerKind.manual, _) => null,
      (TimerKind.pomodoro, TimerPhase.focus) => s.pomodoroFocus,
      (TimerKind.pomodoro, TimerPhase.shortBreak) => s.pomodoroShort,
      (TimerKind.pomodoro, TimerPhase.longBreak) => s.pomodoroLong,
      (TimerKind.deepFocus, TimerPhase.focus) => s.deepFocus,
      (TimerKind.deepFocus, _) => s.deepBreak,
      (TimerKind.sprint, _) => s.sprint,
      (TimerKind.countdown, _) => s.countdown,
    };
    return minutes == null ? null : Duration(minutes: minutes);
  }

  /// What the big clock shows: time left, or time elapsed for the stopwatch.
  Duration get display {
    final len = phaseLength;
    if (len == null) return elapsed;
    final left = len - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  /// 0..1 progress around the ring. The stopwatch laps once an hour.
  double get progress {
    final len = phaseLength;
    final ms = elapsed.inMilliseconds;
    if (len == null) return (ms % 3600000) / 3600000;
    return (ms / len.inMilliseconds).clamp(0.0, 1.0);
  }

  int get roundsPerCycle => store.settings.pomodoroRounds;

  void selectKind(TimerKind k) {
    if (k == kind) return;
    _resetState();
    kind = k;
    completedRounds = 0;
    _notify((n) => n.stopped());
    _changed();
  }

  void setLength(int minutes) {
    store.updateSettings((s) {
      if (kind == TimerKind.sprint) s.sprint = minutes;
      if (kind == TimerKind.countdown) s.countdown = minutes;
    });
    notifyListeners();
  }

  void start() {
    if (isRunning) return;
    if (phase == TimerPhase.focus && _focusStartedAt == null) {
      _focusStartedAt = _clock();
    }
    _runningSince = _clock();
    status = TimerStatus.running;
    _startTicker();
    _notify(_notifyRunning);
    _changed();
  }

  void pause() {
    if (!isRunning) return;
    _banked = elapsed;
    _runningSince = null;
    status = TimerStatus.paused;
    _stopTicker();
    final left = display;
    if (store.settings.notifications) {
      _notify((n) => n.paused(_title, left));
    }
    _changed();
  }

  void toggle() => isRunning ? pause() : start();

  /// Back to the start of the focus phase; nothing is logged.
  void reset() {
    _resetState();
    phase = TimerPhase.focus;
    _notify((n) => n.stopped());
    _changed();
  }

  /// Ends a focus stretch early and asks for the word count.
  void finish() {
    if (phase.isBreak) return;
    final secs = elapsed.inSeconds;
    if (secs < 1) return;
    pendingLog = PendingLog(
      start: _focusStartedAt ?? _clock().subtract(elapsed),
      seconds: secs,
      kind: kind,
      completed: false,
    );
    _resetState();
    _notify((n) => n.stopped());
    _changed();
  }

  /// Skips the current break.
  void skipBreak() {
    if (!phase.isBreak) return;
    _resetState();
    phase = TimerPhase.focus;
    _notify((n) => n.stopped());
    _changed();
  }

  /// Called by the UI once the pending log has been saved or dismissed.
  void consumePendingLog() {
    pendingLog = null;
    if (phase.isBreak && store.settings.autoStartBreaks && isIdle) {
      start();
    } else {
      _changed();
    }
  }

  void _complete() {
    final len = phaseLength;
    if (len == null) return;
    _stopTicker();
    completions++;
    HapticFeedback.heavyImpact();
    // The scheduled "time's up" notification (with its chime) fires on its
    // own; just clear the running countdown.
    _notify((n) => n.finished());
    if (phase == TimerPhase.focus) {
      pendingLog = PendingLog(
        start: _focusStartedAt ?? _clock().subtract(len),
        seconds: len.inSeconds,
        kind: kind,
        completed: true,
      );
      _resetState();
      if (kind.hasBreaks) {
        completedRounds++;
        phase = completedRounds % roundsPerCycle == 0
            ? TimerPhase.longBreak
            : TimerPhase.shortBreak;
      }
    } else {
      _resetState();
      phase = TimerPhase.focus;
    }
    _changed();
  }

  String get _title =>
      '${kind.countsUp ? 'Writing' : phase.label} · ${kind.label}';

  Future<void> _queue = Future.value();

  /// Runs notification work strictly in order, so a quick start→reset can
  /// never leave a stale "running" notification behind.
  void _notify(Future<void> Function(TimerNotifier n) work) {
    final n = notifier;
    if (n == null) return;
    _queue = _queue.then((_) => work(n)).catchError((Object _) {});
  }

  Future<void> _notifyRunning(TimerNotifier n) async {
    if (!store.settings.notifications) {
      await n.stopped();
      return;
    }
    if (!_askedPermission) {
      _askedPermission = true;
      await n.requestPermission();
    }
    // The timer may have been paused or reset while we waited.
    if (!isRunning) return;
    final len = phaseLength;
    final now = _clock();
    await n.running(
      TimerNotice(
        title: _title,
        isBreak: phase.isBreak,
        countsUp: len == null,
        anchor: len == null ? now.subtract(elapsed) : now.add(len - elapsed),
        length: len,
      ),
      sound: store.settings.chime,
    );
  }

  void _resetState() {
    _stopTicker();
    _banked = Duration.zero;
    _runningSince = null;
    _focusStartedAt = null;
    status = TimerStatus.idle;
  }

  void _tick() {
    final len = phaseLength;
    if (len != null && elapsed >= len) {
      _complete();
    } else {
      notifyListeners();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isRunning) _tick();
  }

  void _changed() {
    _syncWakelock();
    _persist();
    notifyListeners();
  }

  void _syncWakelock() {
    final want = isRunning && store.settings.keepScreenOn;
    WakelockPlus.toggle(enable: want).catchError((Object _) {});
  }

  void _persist() {
    _prefs.setString(
      _key,
      jsonEncode({
        'kind': kind.name,
        'phase': phase.name,
        'status': status.name,
        'rounds': completedRounds,
        'bankedMs': _banked.inMilliseconds,
        'since': _runningSince?.toIso8601String(),
        'focusStart': _focusStartedAt?.toIso8601String(),
      }),
    );
  }

  void _restore() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final k = TimerKind.parse(j['kind'] as String?);
      kind = k == TimerKind.manual ? TimerKind.pomodoro : k;
      phase = TimerPhase.values.byName(j['phase'] as String);
      status = TimerStatus.values.byName(j['status'] as String);
      completedRounds = (j['rounds'] as num?)?.toInt() ?? 0;
      _banked = Duration(milliseconds: (j['bankedMs'] as num?)?.toInt() ?? 0);
      final since = j['since'] as String?;
      _runningSince = since == null ? null : DateTime.parse(since);
      final fs = j['focusStart'] as String?;
      _focusStartedAt = fs == null ? null : DateTime.parse(fs);
      if (isRunning) {
        // Settle anything that finished while the app was closed.
        scheduleMicrotask(_tick);
        _startTicker();
      }
    } catch (e) {
      debugPrint('Inkwood: could not restore timer: $e');
    }
  }

  @override
  void dispose() {
    _stopTicker();
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(notifyListeners);
    super.dispose();
  }
}
