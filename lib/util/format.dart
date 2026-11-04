import 'package:intl/intl.dart';

final _decimal = NumberFormat.decimalPattern();
final _compact = NumberFormat.compact();

/// 1,240
String fmtInt(num n) => _decimal.format(n.round());

/// 1,240 · 12.4K · 1.2M — separators below 10k, compact above.
String fmtCompact(num n) => n.abs() < 10000 ? fmtInt(n) : _compact.format(n);

/// Axis labels are always short.
String fmtAxis(num n) => n.abs() < 1000 ? fmtInt(n) : _compact.format(n);

/// 42m · 3h 20m · 45s
String fmtDuration(int seconds) {
  if (seconds <= 0) return '0m';
  if (seconds < 60) return '${seconds}s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// 24:59 · 1:02:03
String fmtClock(Duration d) {
  final s = d.inSeconds.abs();
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime todayDate() => dayOf(DateTime.now());

DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// Calendar days from [a] to [b], immune to DST shifts.
int daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDayKey(String k) {
  final parts = k.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int daysInMonth(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Rounds up to a "nice" axis maximum (1, 2, 2.5, 5 × 10ⁿ).
double niceCeil(double v) {
  if (v <= 0) return 100;
  var mag = 1.0;
  while (mag * 10 <= v) {
    mag *= 10;
  }
  while (mag > v) {
    mag /= 10;
  }
  for (final step in [1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
    if (step * mag >= v) return step * mag;
  }
  return 10 * mag;
}

String hourLabel(int h) {
  final suffix = h < 12 ? 'am' : 'pm';
  final hh = h % 12 == 0 ? 12 : h % 12;
  return '$hh$suffix';
}
