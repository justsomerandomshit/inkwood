import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../util/format.dart';

/// What the timer is doing, as far as notifications are concerned.
class TimerNotice {
  const TimerNotice({
    required this.title,
    required this.isBreak,
    required this.countsUp,
    required this.anchor,
    this.length,
  });

  /// e.g. "Focus · Pomodoro".
  final String title;
  final bool isBreak;
  final bool countsUp;

  /// End time for countdowns, start time for the count-up stopwatch.
  final DateTime anchor;

  /// Full phase length (null for the stopwatch).
  final Duration? length;
}

/// Android notifications for the timer:
///
/// * an ongoing, silent notification with a live countdown while it runs;
/// * an exact, scheduled "time's up" notification with a wooden chime that
///   fires even if the app is in the background or has been closed.
class TimerNotifier {
  TimerNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const _runningId = 1;
  static const _doneId = 2;
  static const _oak = Color(0xFF7A4E2D);
  static const _icon = 'ic_stat_inkwood';

  static const _runningChannel = AndroidNotificationChannel(
    'timer_running',
    'Running timer',
    description: 'A quiet countdown while a timer is running.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );
  static const _focusChannel = AndroidNotificationChannel(
    'timer_focus_done',
    'Focus finished',
    description: 'Chimes when a writing session ends.',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('chime_focus'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
  static const _breakChannel = AndroidNotificationChannel(
    'timer_break_done',
    'Break finished',
    description: 'Chimes when a break ends.',
    importance: Importance.high,
    sound: RawResourceAndroidNotificationSound('chime_break'),
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );
  static const _silentChannel = AndroidNotificationChannel(
    'timer_done_silent',
    'Timer finished (no sound)',
    description: 'Used when the chime is turned off in settings.',
    importance: Importance.high,
    playSound: false,
  );

  bool _ready = false;
  bool _exact = true;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> init() async {
    if (_ready || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      // Scheduling uses absolute instants, so UTC is all we need.
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_icon),
        ),
      );
      final android = _android;
      for (final c in [
        _runningChannel,
        _focusChannel,
        _breakChannel,
        _silentChannel,
      ]) {
        await android?.createNotificationChannel(c);
      }
      _exact = await android?.canScheduleExactNotifications() ?? true;
      _ready = true;
    } catch (e) {
      debugPrint('Inkwood: notifications unavailable: $e');
    }
  }

  /// Asks for permission (Android 13+). Call from a user action.
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _android?.requestNotificationsPermission();
    } catch (_) {}
  }

  /// Timer started or resumed.
  Future<void> running(TimerNotice n, {required bool sound}) async {
    if (!_ready) return;
    final remaining = n.countsUp ? null : n.anchor.difference(DateTime.now());
    final body = n.countsUp
        ? 'Started at ${_time(n.anchor)}'
        : 'Ends at ${_time(n.anchor)}';
    await _safe(
      () => _plugin.show(
        id: _runningId,
        title: n.title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _runningChannel.id,
            _runningChannel.name,
            channelDescription: _runningChannel.description,
            icon: _icon,
            color: _oak,
            importance: Importance.low,
            priority: Priority.low,
            category: AndroidNotificationCategory.stopwatch,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: n.anchor.millisecondsSinceEpoch,
            usesChronometer: true,
            chronometerCountDown: !n.countsUp,
            // Clears itself at the end even if the app was closed.
            timeoutAfter: remaining?.inMilliseconds,
            visibility: NotificationVisibility.public,
          ),
        ),
      ),
    );
    await _cancel(_doneId);
    if (!n.countsUp && remaining != null && !remaining.isNegative) {
      await _scheduleDone(n, sound: sound);
    }
  }

  /// Timer paused: a dismissible note showing what's left.
  Future<void> paused(String title, Duration left) async {
    if (!_ready) return;
    await _cancel(_doneId);
    await _safe(
      () => _plugin.show(
        id: _runningId,
        title: '$title · paused',
        body: '${fmtClock(left)} left',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _runningChannel.id,
            _runningChannel.name,
            icon: _icon,
            color: _oak,
            importance: Importance.low,
            priority: Priority.low,
            showWhen: false,
          ),
        ),
      ),
    );
  }

  /// Timer reached its end (the scheduled notification takes it from here).
  Future<void> finished() => _cancel(_runningId);

  /// Timer reset, skipped or switched: clear everything.
  Future<void> stopped() async {
    await _cancel(_runningId);
    await _cancel(_doneId);
  }

  Future<void> _scheduleDone(TimerNotice n, {required bool sound}) async {
    final channel = !sound
        ? _silentChannel
        : n.isBreak
        ? _breakChannel
        : _focusChannel;
    final minutes = n.length?.inMinutes ?? 0;
    final title = n.isBreak ? 'Break\'s over' : 'Session complete';
    final body = n.isBreak
        ? 'Back to the page whenever you\'re ready.'
        : '$minutes ${minutes == 1 ? 'minute' : 'minutes'} of writing done. '
              'Open Inkwood to log your words.';
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: _icon,
        color: _oak,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.alarm,
        sound: channel.sound,
        playSound: channel.playSound,
        audioAttributesUsage: channel.audioAttributesUsage,
        styleInformation: BigTextStyleInformation(body),
        ticker: title,
        visibility: NotificationVisibility.public,
      ),
    );
    final at = tz.TZDateTime.from(n.anchor, tz.UTC);
    await _safe(() async {
      try {
        await _plugin.zonedSchedule(
          id: _doneId,
          scheduledDate: at,
          notificationDetails: details,
          androidScheduleMode: _exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
        );
      } on Exception {
        // Exact alarms revoked: fall back to an inexact one.
        _exact = false;
        await _plugin.zonedSchedule(
          id: _doneId,
          scheduledDate: at,
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
        );
      }
    });
  }

  Future<void> _cancel(int id) async {
    if (!_ready) return;
    await _safe(() => _plugin.cancel(id: id));
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('Inkwood: notification error: $e');
    }
  }

  static String _time(DateTime t) => DateFormat.jm().format(t);
}
