import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/writing_store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/day_sheet.dart';
import 'settings_screen.dart';

const _baseYear = 2000;
int _indexOf(DateTime m) => (m.year - _baseYear) * 12 + m.month - 1;
DateTime _monthAt(int i) => DateTime(_baseYear + i ~/ 12, i % 12 + 1);

/// 0–4 intensity relative to that day's goal.
int heatLevel(int words, int goal, DayMark? mark) {
  if (mark == DayMark.done || (goal > 0 && words >= goal)) return 4;
  if (words <= 0) return 0;
  final r = words / goal;
  if (r < 0.34) return 1;
  if (r < 0.67) return 2;
  return 3;
}

class HeatmapScreen extends StatefulWidget {
  const HeatmapScreen({super.key});

  @override
  State<HeatmapScreen> createState() => _HeatmapScreenState();
}

class _HeatmapScreenState extends State<HeatmapScreen> {
  late final int _current = _indexOf(DateTime.now());
  late final PageController _pages = PageController(initialPage: _current);
  late int _visible = _current;

  DateTime get _month => _monthAt(_visible);

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _go(int index) {
    _pages.animateToPage(
      index.clamp(0, _current),
      duration: Motion.of(context, Motion.long),
      curve: Motion.enter,
    );
  }

  Future<void> _editGoal(WritingStore store) async {
    final c = TextEditingController(text: '${store.currentGoal}');
    final goal = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Daily word goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pick something you can hit on an ordinary day. '
              'Past days keep the goal they had.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Words per day'),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final g in [250, 500, 1000, 1667])
                  ActionChip(
                    label: Text(fmtInt(g)),
                    onPressed: () => c.text = '$g',
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(c.text)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    c.dispose();
    if (goal != null && goal > 0) store.setGoal(goal);
  }

  Future<void> _startFresh(WritingStore store) async {
    var erase = false;
    final monthName = DateFormat.yMMMM().format(_month);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          icon: const Icon(Icons.restart_alt),
          title: const Text('Start fresh?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Your streak and goal tracking begin again from today. '
                'Earlier days stay in your history, dimmed.',
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: erase,
                onChanged: (v) => set(() => erase = v ?? false),
                title: Text('Also erase everything in $monthName'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start fresh'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final before = store.snapshot();
    if (erase) store.clearMonth(_month);
    store.startFresh(store.today);
    _undoable(store, before, 'Fresh start from today');
  }

  Future<void> _markMonth(WritingStore store) async {
    final month = _month;
    final choice = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Mark ${DateFormat.yMMMM().format(month)}',
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Every past day as goal met'),
              subtitle: const Text('For months you wrote before using Inkwood'),
              onTap: () => Navigator.pop(ctx, 0),
            ),
            ListTile(
              leading: const Icon(Icons.bedtime_outlined),
              title: const Text('Unwritten days as rest days'),
              subtitle: const Text('Keeps streaks intact across a break'),
              onTap: () => Navigator.pop(ctx, 1),
            ),
            ListTile(
              leading: const Icon(Icons.layers_clear_outlined),
              title: const Text('Clear all marks'),
              onTap: () => Navigator.pop(ctx, 2),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    final before = store.snapshot();
    switch (choice) {
      case 0:
        store.markMonth(month, DayMark.done);
      case 1:
        store.markMonth(
          month,
          DayMark.rest,
          where: (d) => store.wordsOn(d) == 0 && store.markOn(d) == null,
        );
      case 2:
        store.markMonth(month, null);
    }
    _undoable(store, before, 'Month updated');
  }

  void _undoable(WritingStore store, StoreSnapshot before, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restore(before),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: const Text('Word goal'),
            actions: [
              MenuAnchor(
                builder: (context, menu, _) => IconButton(
                  tooltip: 'More',
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  icon: const Icon(Icons.more_vert),
                ),
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.today_outlined),
                    onPressed: () => _go(_current),
                    child: const Text('Jump to today'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.checklist),
                    onPressed: () => _markMonth(store),
                    child: const Text('Mark this month…'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.restart_alt),
                    onPressed: () => _startFresh(store),
                    child: const Text('Start fresh…'),
                  ),
                  if (store.freshStart != null)
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.history),
                      onPressed: store.clearFreshStart,
                      child: const Text('Count all history again'),
                    ),
                ],
              ),
              const SettingsButton(),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            sliver: SliverList.list(
              children: [
                _GoalRow(store: store, onEdit: () => _editGoal(store)),
                const SizedBox(height: 16),
                Card.outlined(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Previous month',
                              onPressed: _visible > 0
                                  ? () => _go(_visible - 1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: Motion.of(context, Motion.medium),
                                child: Text(
                                  DateFormat.yMMMM().format(_month),
                                  key: ValueKey(_visible),
                                  textAlign: TextAlign.center,
                                  style: t.titleMedium,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Next month',
                              onPressed: _visible < _current
                                  ? () => _go(_visible + 1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Column(
                            children: [
                              const _WeekdayHeader(),
                              const SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, box) {
                                  const gap = 4.0;
                                  final cell = (box.maxWidth - gap * 6) / 7;
                                  return SizedBox(
                                    height: cell * 6 + gap * 5,
                                    child: PageView.builder(
                                      controller: _pages,
                                      itemCount: _current + 1,
                                      onPageChanged: (i) =>
                                          setState(() => _visible = i),
                                      itemBuilder: (_, i) => _MonthGrid(
                                        month: _monthAt(i),
                                        cell: cell,
                                        gap: gap,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              const _Legend(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _MonthSummary(store: store, month: _month),
                const SizedBox(height: 16),
                Text(
                  'Tap a day to see or log its writing. '
                  'Long-press to mark it as goal met.',
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
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.store, required this.onEdit});
  final WritingStore store;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final streak = store.currentStreak;
    final best = store.bestStreak;

    Widget header(IconData icon, String label, {Widget? trailing}) => Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        ?trailing,
      ],
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Card.filled(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header(Icons.local_fire_department_outlined, 'Streak'),
                    const SizedBox(height: 12),
                    AnimatedCount(
                      streak,
                      suffix: streak == 1 ? ' day' : ' days',
                      style: t.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      streak == 0 && best > 0
                          ? 'Best $best. Write today to start again'
                          : streak == 0
                          ? 'Write today to start'
                          : 'Best $best',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Card.filled(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header(
                        Icons.flag_outlined,
                        'Daily goal',
                        trailing: Icon(
                          Icons.edit_outlined,
                          size: 18,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      AnimatedCount(store.currentGoal, style: t.headlineSmall),
                      const SizedBox(height: 4),
                      Text(
                        'words a day',
                        style: t.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat.E();
    // 2024-01-01 was a Monday.
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Text(
              fmt.format(DateTime(2024, 1, 1 + i)).substring(0, 1),
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.cell,
    required this.gap,
  });
  final DateTime month;
  final double cell;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final leading = DateTime(month.year, month.month, 1).weekday - 1;
    final days = daysInMonth(month);
    final today = store.today;
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (var i = 0; i < leading; i++) SizedBox(width: cell, height: cell),
        for (var d = 1; d <= days; d++)
          _DayCell(
            day: DateTime(month.year, month.month, d),
            size: cell,
            index: leading + d,
            store: store,
            today: today,
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.size,
    required this.index,
    required this.store,
    required this.today,
  });

  final DateTime day;
  final double size;
  final int index;
  final WritingStore store;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final heat = CozyColors.of(context).heat;
    final future = day.isAfter(today);
    final isToday = sameDay(day, today);
    final words = store.wordsOn(day);
    final goal = store.goalFor(day);
    final mark = store.markOn(day);
    final level = future ? 0 : heatLevel(words, goal, mark);
    final dimmed = store.isBeforeFreshStart(day);
    final met = !future && level == 4;
    final bg = future ? Colors.transparent : heat[level];
    // Light heat tones take the dark "on" role, dark tones the light one.
    final fg = future
        ? cs.outline
        : level == 4
        ? cs.surfaceContainerLowest
        : cs.onSurface;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: isToday
          ? BorderSide(color: cs.onSurface, width: 2)
          : BorderSide.none,
    );

    final cell = AnimatedContainer(
      duration: Motion.of(context, Motion.medium),
      curve: Motion.standard,
      width: size,
      height: size,
      decoration: ShapeDecoration(color: bg, shape: shape),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: future ? null : () => showDaySheet(context, day),
          onLongPress: future
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  store.setMark(
                    day,
                    mark == DayMark.done ? null : DayMark.done,
                  );
                },
          child: Stack(
            children: [
              Center(
                child: Text(
                  '${day.day}',
                  style: t.labelLarge?.copyWith(
                    color: fg,
                    fontWeight: isToday ? FontWeight.w800 : null,
                  ),
                ),
              ),
              if (mark == DayMark.rest || met)
                Positioned(
                  right: 4,
                  top: 4,
                  child: Icon(
                    mark == DayMark.rest ? Icons.bedtime : Icons.check,
                    size: max(10, size * 0.22),
                    color: fg,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // A gentle staggered settle when a month comes into view.
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) == true;
    final animated = reduce
        ? cell
        : TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 250 + index * 10),
            curve: Motion.enter,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
            ),
            child: cell,
          );

    return Semantics(
      label:
          '${DateFormat.MMMMd().format(day)}: ${fmtInt(words)} words'
          '${met ? ', goal met' : ''}${mark == DayMark.rest ? ', rest day' : ''}',
      child: Opacity(opacity: dimmed ? 0.38 : 1, child: animated),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final heat = CozyColors.of(context).heat;
    final style = t.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    Widget swatch(Color c) => Container(
      width: 16,
      height: 16,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Text('Less', style: style),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: heat.map(swatch).toList(),
        ),
        Text('Goal met', style: style),
        const SizedBox(width: 8),
        Icon(Icons.bedtime, size: 16, color: cs.onSurfaceVariant),
        Text('Rest day', style: style),
      ],
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.store, required this.month});
  final WritingStore store;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    var words = 0, met = 0, counted = 0, writing = 0, best = 0, secs = 0;
    for (var d = 1; d <= daysInMonth(month); d++) {
      final day = DateTime(month.year, month.month, d);
      if (day.isAfter(store.today)) break;
      final w = store.wordsOn(day);
      words += w;
      secs += store.secondsOn(day);
      best = max(best, w);
      if (w > 0) writing++;
      if (store.isBeforeFreshStart(day)) continue;
      counted++;
      if (store.goalMetOn(day)) met++;
    }
    Widget stat(String label, Widget value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(style: t.titleLarge, child: value),
          const SizedBox(height: 4),
          Text(label, style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
    return SectionCard(
      title: DateFormat.MMMM().format(month),
      subtitle: counted == 0
          ? 'Nothing counted yet'
          : 'Goal met on $met of $counted days',
      child: Column(
        children: [
          Row(
            children: [
              stat('Words', AnimatedCount(words, format: fmtCompact)),
              stat('Writing time', Text(fmtDuration(secs))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              stat(
                'Avg on writing days',
                AnimatedCount(writing == 0 ? 0 : words ~/ writing),
              ),
              stat('Best day', AnimatedCount(best)),
            ],
          ),
        ],
      ),
    );
  }
}
