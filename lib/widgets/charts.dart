import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/stats.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';

/// Shared look for every chart: thin, quiet gridlines, no borders, compact
/// left-axis labels at 0 / mid / max (Tufte: spend ink on data, not frames).
class _ChartStyle {
  _ChartStyle(BuildContext context)
    : cs = Theme.of(context).colorScheme,
      axis = Theme.of(context).textTheme.labelSmall!
          .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      tip = Theme.of(context).textTheme.labelMedium!
          .copyWith(color: Theme.of(context).colorScheme.onInverseSurface),
      strong = CozyColors.of(context).heat[4],
      soft = CozyColors.of(context).heat[2];
  final ColorScheme cs;

  /// Mid-brown data colours from the heat ramp: goal met / not met.
  final Color strong;
  final Color soft;
  final TextStyle axis;
  final TextStyle tip;

  FlGridData grid(double maxY) => FlGridData(
    drawVerticalLine: false,
    horizontalInterval: maxY / 2,
    getDrawingHorizontalLine: (_) =>
        FlLine(color: cs.onSurface.withValues(alpha: 0.08), strokeWidth: 1),
  );

  AxisTitles leftAxis(double maxY) => AxisTitles(
    sideTitles: SideTitles(
      showTitles: true,
      reservedSize: 44,
      interval: maxY / 2,
      getTitlesWidget: (v, meta) => SideTitleWidget(
        meta: meta,
        child: Text(fmtAxis(v), style: axis),
      ),
    ),
  );

  static const none = AxisTitles(sideTitles: SideTitles(showTitles: false));
}

/// Plays the data in from zero on first build (charts grow, not pop).
mixin _GrowIn<T extends StatefulWidget> on State<T> {
  bool shown = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => shown = true);
    });
  }
}

/// Words per day (or month) as bars, with a dashed goal line on daily views.
class WordsBarChart extends StatefulWidget {
  const WordsBarChart({super.key, required this.stats});
  final RangeStats stats;

  @override
  State<WordsBarChart> createState() => _WordsBarChartState();
}

class _WordsBarChartState extends State<WordsBarChart> with _GrowIn {
  bool _showLabel(int i, int n) {
    final r = widget.stats.range;
    if (r == StatsRange.week || n <= 12) return true;
    if (r == StatsRange.month) return (n - 1 - i) % 7 == 0;
    final step = (n / 5).ceil();
    return (n - 1 - i) % step == 0;
  }

  @override
  Widget build(BuildContext context) {
    final s = _ChartStyle(context);
    final st = widget.stats;
    final buckets = st.buckets;
    final n = buckets.length;
    final goal = st.daily && buckets.isNotEmpty ? buckets.last.goal! : null;
    final peak = maxOf(buckets.map((b) => b.words)).toDouble();
    final maxY = niceCeil(max(peak, (goal ?? 0).toDouble()) * 1.1);
    final barWidth = n <= 7 ? 22.0 : (n <= 12 ? 16.0 : 6.0);

    return AspectRatio(
      aspectRatio: 1.7,
      child: BarChart(
        duration: Motion.of(context, Motion.long),
        curve: Motion.enter,
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: s.grid(maxY),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: _ChartStyle.none,
            rightTitles: _ChartStyle.none,
            leftTitles: s.leftAxis(maxY),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= n || !_showLabel(i, n)) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(buckets[i].label, style: s.axis),
                  );
                },
              ),
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              if (goal != null)
                HorizontalLine(
                  y: goal.toDouble(),
                  color: s.cs.onSurfaceVariant,
                  strokeWidth: 1.5,
                  dashArray: [6, 4],
                  label: HorizontalLineLabel(
                    show: false,
                    alignment: Alignment.topRight,
                    padding: const EdgeInsets.only(bottom: 4),
                    style: s.axis.copyWith(
                      color: s.cs.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                    labelResolver: (_) => 'Goal ${fmtCompact(goal)}',
                  ),
                ),
            ],
          ),
          barTouchData: BarTouchData(
            touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 6),
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => s.cs.inverseSurface,
              tooltipBorderRadius: BorderRadius.circular(10),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (group, gi, rod, ri) {
                final b = buckets[group.x];
                final when = st.daily
                    ? DateFormat.MMMEd().format(b.start)
                    : b.label;
                final parts = [
                  '${fmtInt(b.words)} words',
                  if (b.seconds > 0) fmtDuration(b.seconds),
                  if (b.goalMet) 'goal ✓',
                ];
                return BarTooltipItem(
                  '$when\n',
                  s.tip.copyWith(fontWeight: FontWeight.w800),
                  children: [TextSpan(text: parts.join(' · '), style: s.tip)],
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: shown ? buckets[i].words.toDouble() : 0,
                    width: barWidth,
                    // Stronger brown when the goal was met. Never red/green.
                    color: (!st.daily || buckets[i].goalMet)
                        ? s.strong
                        : s.soft,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Running total vs. the goal pace ("par") line, as NaNoWriMo charts it.
class CumulativeChart extends StatefulWidget {
  const CumulativeChart({super.key, required this.stats});
  final RangeStats stats;

  @override
  State<CumulativeChart> createState() => _CumulativeChartState();
}

class _CumulativeChartState extends State<CumulativeChart> with _GrowIn {
  @override
  Widget build(BuildContext context) {
    final s = _ChartStyle(context);
    final st = widget.stats;
    final data = st.cumulative;
    final par = st.par;
    final n = data.length;
    final maxY = niceCeil(max(data.last, par.last).toDouble() * 1.05);
    // Keep at most ~120 points so long ranges stay light.
    final step = max(1, (n / 120).ceil());
    List<FlSpot> spots(List<int> src) => [
      for (var i = 0; i < n; i += step)
        FlSpot(i.toDouble(), shown ? src[i].toDouble() : 0),
      if ((n - 1) % step != 0)
        FlSpot((n - 1).toDouble(), shown ? src[n - 1].toDouble() : 0),
    ];
    final fmt = DateFormat.MMMd();

    return AspectRatio(
      aspectRatio: 1.7,
      child: LineChart(
        duration: Motion.of(context, Motion.long),
        curve: Motion.enter,
        LineChartData(
          minX: 0,
          maxX: (n - 1).toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: s.grid(maxY),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: _ChartStyle.none,
            rightTitles: _ChartStyle.none,
            leftTitles: s.leftAxis(maxY),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: max(1, (n - 1) / 3).toDouble(),
                getTitlesWidget: (v, meta) {
                  final d = addDays(st.start, v.round());
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(fmt.format(d), style: s.axis),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => s.cs.inverseSurface,
              tooltipBorderRadius: BorderRadius.circular(10),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (spots) => [
                for (final sp in spots)
                  LineTooltipItem(
                    sp.barIndex == 0
                        ? '${fmt.format(addDays(st.start, sp.x.round()))}\n${fmtInt(sp.y)} words'
                        : 'Goal pace ${fmtInt(sp.y)}',
                    s.tip,
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots(data),
              isCurved: false,
              color: s.strong,
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    s.strong.withValues(alpha: 0.35),
                    s.strong.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
            LineChartBarData(
              spots: spots(par),
              isCurved: false,
              color: s.cs.onSurfaceVariant,
              barWidth: 1.5,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

/// Words by hour of day (24 bars) or by weekday (7 bars).
class RhythmChart extends StatefulWidget {
  const RhythmChart({super.key, required this.values, required this.byHour});
  final List<int> values;
  final bool byHour;

  @override
  State<RhythmChart> createState() => _RhythmChartState();
}

class _RhythmChartState extends State<RhythmChart> with _GrowIn {
  @override
  Widget build(BuildContext context) {
    final s = _ChartStyle(context);
    final v = widget.values;
    final peak = maxOf(v);
    final maxY = niceCeil(peak * 1.1);
    final weekday = DateFormat.E();
    String label(int i) =>
        widget.byHour ? hourLabel(i) : weekday.format(DateTime(2024, 1, 1 + i));

    return AspectRatio(
      aspectRatio: 2,
      child: BarChart(
        duration: Motion.of(context, Motion.long),
        curve: Motion.enter,
        BarChartData(
          minY: 0,
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: s.grid(maxY),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: _ChartStyle.none,
            rightTitles: _ChartStyle.none,
            leftTitles: s.leftAxis(maxY),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                interval: 1,
                getTitlesWidget: (x, meta) {
                  final i = x.toInt();
                  if (widget.byHour && i % 6 != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      widget.byHour ? label(i) : label(i).substring(0, 1),
                      style: s.axis,
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchExtraThreshold: const EdgeInsets.symmetric(horizontal: 4),
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => s.cs.inverseSurface,
              tooltipBorderRadius: BorderRadius.circular(10),
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                widget.byHour
                    ? '${label(g.x)}–${hourLabel((g.x + 1) % 24)}\n'
                    : '${label(g.x)}\n',
                s.tip.copyWith(fontWeight: FontWeight.w800),
                children: [
                  TextSpan(text: '${fmtInt(v[g.x])} words', style: s.tip),
                ],
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < v.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: shown ? v[i].toDouble() : 0,
                    width: widget.byHour ? 7 : 22,
                    color: v[i] == peak && peak > 0 ? s.strong : s.soft,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal bars with direct labels — no legend needed.
class ModePaceBars extends StatelessWidget {
  const ModePaceBars({super.key, required this.kinds});
  final List<KindStat> kinds;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final top = kinds.map((k) => k.pace).reduce(max);
    return Column(
      children: [
        for (final (i, k) in kinds.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Row(
                    children: [
                      Icon(k.kind.icon, size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          k.kind.label,
                          style: t.labelLarge,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => Align(
                      alignment: Alignment.centerLeft,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: k.pace / top),
                        duration: Motion.of(
                          context,
                          Motion.long + Duration(milliseconds: 80 * i),
                        ),
                        curve: Motion.enter,
                        builder: (context, f, _) => Container(
                          height: 22,
                          width: max(4, box.maxWidth * f),
                          decoration: BoxDecoration(
                            color: i == 0
                                ? CozyColors.of(context).heat[4]
                                : CozyColors.of(context).heat[2],
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: Text(
                    '${fmtCompact(k.pace)} w/h',
                    textAlign: TextAlign.right,
                    style: t.labelLarge,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
