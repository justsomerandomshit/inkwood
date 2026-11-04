import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/stats.dart';
import '../data/writing_store.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import '../widgets/day_sheet.dart';
import 'settings_screen.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key, required this.onStartSession});

  final VoidCallback onStartSession;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  StatsRange _range = StatsRange.month;
  bool _byHour = true;
  int _recentShown = 5;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    if (store.sessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Your writing'),
          actions: const [SettingsButton()],
        ),
        body: _EmptyStats(onStart: widget.onStartSession),
      );
    }

    final st = computeStats(store, _range);
    final bests = computeBests(store);
    final projection = monthProjection(store);
    var i = 0;
    Widget stagger(Widget w) => FadeSlideIn(
      key: ValueKey('$_range-$i'),
      delay: Duration(milliseconds: 50 * i++),
      child: w,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Your writing'),
            actions: const [SettingsButton()],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                SegmentedButton<StatsRange>(
                  segments: [
                    for (final r in StatsRange.values)
                      ButtonSegment(value: r, label: Text(r.label)),
                  ],
                  selected: {_range},
                  // Four segments don't fit a checkmark at phone width.
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _range = s.first),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  switchInCurve: Motion.enter,
                  child: Column(
                    key: ValueKey(_range),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      stagger(_Hero(stats: st, store: store)),
                      stagger(_Habits(stats: st, store: store)),
                      stagger(
                        Section(
                          title: st.daily ? 'Words per day' : 'Words per month',
                          subtitle: st.daily
                              ? 'Goal met on ${st.goalMetDays} of ${st.countedDays} days. Dashed line: ${fmtInt(store.currentGoal)} goal'
                              : '${st.range.caption} · ${fmtCompact(st.words)} words',
                          child: WordsBarChart(stats: st),
                        ),
                      ),
                      if (_range != StatsRange.week && st.writingDays >= 2) ...[
                        stagger(
                          Section(
                            title: 'Running total',
                            subtitle:
                                _range == StatsRange.month && projection != null
                                ? 'At this pace: ~${fmtCompact(projection.projected)} words by ${DateFormat.MMMd().format(projection.monthEnd)}'
                                : 'Your words vs. the goal pace (dashed)',
                            child: CumulativeChart(stats: st),
                          ),
                        ),
                      ],
                      if (st.showRhythm) ...[
                        stagger(
                          Section(
                            title: 'When you write',
                            subtitle: _rhythmCaption(st),
                            trailing: SegmentedButton<bool>(
                              style: const ButtonStyle(
                                visualDensity: VisualDensity.compact,
                              ),
                              segments: const [
                                ButtonSegment(value: true, label: Text('Hour')),
                                ButtonSegment(value: false, label: Text('Day')),
                              ],
                              selected: {_byHour},
                              onSelectionChanged: (s) =>
                                  setState(() => _byHour = s.first),
                            ),
                            child: AnimatedSwitcher(
                              duration: Motion.of(context, Motion.medium),
                              child: RhythmChart(
                                key: ValueKey(_byHour),
                                values: _byHour ? st.byHour : st.byWeekday,
                                byHour: _byHour,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (st.comparableKinds.isNotEmpty) ...[
                        stagger(
                          Section(
                            title: 'Pace by timer',
                            subtitle:
                                '${st.comparableKinds.first.kind.label} is your fastest: ${fmtCompact(st.comparableKinds.first.pace)} words/hour',
                            child: ModePaceBars(kinds: st.comparableKinds),
                          ),
                        ),
                      ],
                      stagger(_Bests(bests: bests)),
                      stagger(
                        Section(
                          title: 'Recent sessions',
                          subtitle: 'Tap to edit · swipe to remove',
                          child: Column(
                            children: [
                              for (final s in store.sessions.reversed.take(
                                _recentShown,
                              ))
                                SessionTile(session: s, showDate: true),
                              if (store.sessions.length > _recentShown)
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _recentShown += 10),
                                  child: const Text('Show more'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Averages only count days you wrote, so rest days never lower them.',
                  textAlign: TextAlign.center,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _rhythmCaption(RangeStats st) {
    if (_byHour) {
      final b = st.bestHours;
      if (b == null) return 'Words by hour of day';
      return 'Most productive ${hourLabel(b.$1)}–${hourLabel(b.$2)}';
    }
    final d = st.bestWeekday;
    if (d == null) return 'Words by weekday';
    return 'Your strongest day: ${DateFormat.EEEE().format(DateTime(2024, 1, 1 + d))}s';
  }
}

/// The headline figure for the range, with supporting numbers in a strip.
class _Hero extends StatelessWidget {
  const _Hero({required this.stats, required this.store});
  final RangeStats stats;
  final WritingStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final change = stats.change;
    String? delta;
    IconData? deltaIcon;
    if (stats.range != StatsRange.all) {
      final prev = stats.previousWords ?? 0;
      final period = switch (stats.range) {
        StatsRange.week => 'the week before',
        StatsRange.month => 'the 30 days before',
        _ => 'the year before',
      };
      if (change == null) {
        delta = prev == 0 && stats.words > 0
            ? 'New! Nothing to compare with yet'
            : null;
      } else if (change >= 0) {
        deltaIcon = Icons.arrow_upward;
        delta = '${(change * 100).round()}% more than $period';
      } else {
        deltaIcon = Icons.arrow_downward;
        delta = '${fmtInt(prev - stats.words)} fewer than $period';
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          stats.range.caption,
          style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            AnimatedCount(stats.words, style: t.displayMedium),
            const SizedBox(width: 8),
            Text(
              'words',
              style: t.titleLarge?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
        if (delta != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              if (deltaIcon != null) ...[
                Icon(deltaIcon, size: 18, color: cs.primary),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  delta,
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        MetricRow(
          children: [
            Metric(
              value: AnimatedCount(stats.avgOnWritingDays, format: fmtCompact),
              label: 'daily average',
            ),
            Metric(
              value: AnimatedCount(stats.writingDays),
              label: stats.writingDays == 1 ? 'writing day' : 'writing days',
            ),
            Metric(
              value: AnimatedCount(store.totalWords, format: fmtCompact),
              label: 'words all-time',
            ),
          ],
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// Streak, time, pace and session size.
class _Habits extends StatelessWidget {
  const _Habits({required this.stats, required this.store});
  final RangeStats stats;
  final WritingStore store;

  @override
  Widget build(BuildContext context) {
    final streak = store.currentStreak;
    final best = store.bestStreak;
    return Section(
      title: 'Habits',
      child: Column(
        children: [
          MetricRow(
            children: [
              Metric(
                icon: Icons.local_fire_department_outlined,
                value: Text(
                  streak == 0 ? '—' : '$streak ${streak == 1 ? 'day' : 'days'}',
                ),
                label: streak == 0
                    ? 'streak · best $best, write today'
                    : 'streak · best $best',
              ),
              Metric(
                icon: Icons.schedule,
                value: Text(fmtDuration(stats.seconds)),
                label:
                    'writing · ${stats.entries} ${stats.entries == 1 ? 'session' : 'sessions'}',
              ),
            ],
          ),
          const SizedBox(height: 24),
          MetricRow(
            children: [
              Metric(
                icon: Icons.speed,
                value: stats.pace == null
                    ? const Text('—')
                    : AnimatedCount(stats.pace!, suffix: ' w/h'),
                label: 'pace, timed sessions',
              ),
              Metric(
                icon: Icons.notes,
                value: stats.medianSession == null
                    ? const Text('—')
                    : AnimatedCount(stats.medianSession!),
                label: 'typical words per session',
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _Bests extends StatelessWidget {
  const _Bests({required this.bests});
  final PersonalBests bests;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat.yMMMd();
    final rows = <(IconData, String, String)>[
      if (bests.bestDay case final b?)
        (
          Icons.wb_sunny_outlined,
          'Best day',
          '${fmtInt(b.$2)} words · ${fmt.format(b.$1)}',
        ),
      if (bests.bestWeek case final b?)
        (
          Icons.date_range_outlined,
          'Best week',
          '${fmtInt(b.$2)} words · from ${DateFormat.MMMd().format(b.$1)}',
        ),
      if (bests.longestStreak > 0)
        (
          Icons.local_fire_department_outlined,
          'Longest streak',
          '${bests.longestStreak} days',
        ),
      if (bests.longestSession case final s?)
        (
          Icons.hourglass_full_outlined,
          'Longest session',
          '${fmtDuration(s.durationSec)} · ${fmtInt(s.words)} words',
        ),
      if (bests.fastestSession case final s?)
        (
          Icons.bolt_outlined,
          'Fastest session',
          '${fmtInt(s.pace!)} w/h · ${s.kind.label}',
        ),
    ];
    return Section(
      title: 'Personal bests',
      child: Column(
        children: [
          for (final r in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.$1),
              title: Text(r.$2),
              subtitle: Text(r.$3),
            ),
        ],
      ),
    );
  }
}

class _EmptyStats extends StatelessWidget {
  const _EmptyStats({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // A faded preview of the chart to come.
              SizedBox(
                height: 96,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final h in [30, 55, 40, 70, 50, 85, 64])
                      Container(
                        width: 18,
                        height: h.toDouble(),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.18),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Your stats grow here', style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Finish a session or log some words, and your totals, pace and '
                'rhythms will appear — one gentle chart at a time.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: onStart,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Start a session'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                child: const Text('Or explore with sample data'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
