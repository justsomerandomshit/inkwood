import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/timer_controller.dart';
import '../data/writing_store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';
import '../widgets/common.dart';
import '../widgets/log_words_sheet.dart';
import 'settings_screen.dart';

class TimerScreen extends StatelessWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final timer = context.watch<TimerController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Writing desk'),
        actions: const [SettingsButton()],
      ),
      body: LayoutBuilder(
        builder: (context, box) {
          final ring = min(
            box.maxWidth - 96,
            box.maxHeight * 0.36,
          ).clamp(180.0, 300.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _ModePicker(timer: timer),
                  _TimerFace(timer: timer, size: ring),
                  _Controls(timer: timer),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: _TodayCard(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.timer});
  final TimerController timer;

  String _describe(AppSettings s, TimerKind k) => switch (k) {
    TimerKind.pomodoro =>
      '${s.pomodoroFocus} min focus, ${s.pomodoroShort} min break, long break every ${s.pomodoroRounds}',
    TimerKind.deepFocus =>
      '${s.deepFocus} min of deep work, then a ${s.deepBreak} min break',
    TimerKind.sprint => '${s.sprint} min word sprint. No editing, just forward',
    TimerKind.countdown => '${s.countdown} min countdown',
    TimerKind.stopwatch => 'Open-ended. Write until you\'re done',
    TimerKind.manual => '',
  };

  Future<void> _select(BuildContext context, TimerKind k) async {
    if (!timer.isIdle && k != timer.kind) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Switch timer?'),
          content: const Text(
            'Your current timer will stop, and you can log what you wrote.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep going'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Switch'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      if (!timer.phase.isBreak) timer.finish();
    }
    HapticFeedback.selectionClick();
    timer.selectKind(k);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final settings = context.watch<WritingStore>().settings;
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final k in TimerKind.selectable)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(k.icon),
                    label: Text(k.label),
                    selected: timer.kind == k,
                    onSelected: (_) => _select(context, k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: Motion.of(context, Motion.medium),
          child: Padding(
            key: ValueKey('${timer.kind}${_describe(settings, timer.kind)}'),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              _describe(settings, timer.kind),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _TimerFace extends StatefulWidget {
  const _TimerFace({required this.timer, required this.size});
  final TimerController timer;
  final double size;

  @override
  State<_TimerFace> createState() => _TimerFaceState();
}

class _TimerFaceState extends State<_TimerFace>
    with SingleTickerProviderStateMixin {
  // Repaints every frame while running so the indicator sweeps smoothly.
  late final Ticker _ticker = createTicker((_) => setState(() {}));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _TimerFace old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.timer.isRunning && !_ticker.isActive) _ticker.start();
    if (!widget.timer.isRunning && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  Future<void> _editLength() async {
    final timer = widget.timer;
    var value = (timer.phaseLength?.inMinutes ?? 30).toDouble();
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final t = Theme.of(ctx).textTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('${timer.kind.label} length', style: t.titleLarge),
                const SizedBox(height: 16),
                Text(
                  '${value.round()} min',
                  textAlign: TextAlign.center,
                  style: t.displaySmall,
                ),
                const SizedBox(height: 8),
                Slider(
                  value: value,
                  min: 5,
                  max: 120,
                  divisions: 23,
                  label: '${value.round()} min',
                  onChanged: (v) => set(() => value = v),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(ctx, value.round()),
                    child: const Text('Set length'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
    if (result != null) timer.setLength(result);
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.timer;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final size = widget.size;
    final onBreak = timer.phase.isBreak;
    final adjustable = timer.kind.adjustableLength && timer.isIdle;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: timer.progress,
                strokeWidth: 12,
                trackGap: 8,
                strokeCap: StrokeCap.round,
                color: onBreak ? cs.tertiary : cs.primary,
                backgroundColor: cs.secondaryContainer,
                semanticsLabel: 'Timer progress',
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.medium),
                  child: Text(
                    timer.kind.countsUp ? 'Writing' : timer.phase.label,
                    key: ValueKey('${timer.phase}${timer.kind.countsUp}'),
                    style: t.titleMedium?.copyWith(
                      color: onBreak ? cs.tertiary : cs.primary,
                    ),
                  ),
                ),
                Text(
                  fmtClock(timer.display),
                  style: t.displayLarge?.copyWith(
                    fontSize: size * 0.24,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                SizedBox(
                  height: 40,
                  child: timer.kind.hasBreaks
                      ? _RoundDots(
                          done: timer.completedRounds % timer.roundsPerCycle,
                          total: timer.roundsPerCycle,
                          onBreak: onBreak,
                        )
                      : adjustable
                      ? TextButton.icon(
                          onPressed: _editLength,
                          icon: const Icon(Icons.tune),
                          label: const Text('Adjust'),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundDots extends StatelessWidget {
  const _RoundDots({
    required this.done,
    required this.total,
    required this.onBreak,
  });
  final int done;
  final int total;
  final bool onBreak;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // After the last round of a cycle `done` wraps to 0 during the long break.
    final filled = onBreak && done == 0 ? total : done;
    return Semantics(
      label: '$filled of $total rounds done',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++)
            AnimatedContainer(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.enter,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled ? cs.primary : cs.outlineVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.timer});
  final TimerController timer;

  static const _side = EdgeInsets.all(16); // 24dp icon + 16 = 56dp (M)

  @override
  Widget build(BuildContext context) {
    final canReset = !timer.isIdle || timer.phase.isBreak;
    final onBreak = timer.phase.isBreak;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          tooltip: 'Reset',
          padding: _side,
          onPressed: canReset
              ? () {
                  HapticFeedback.lightImpact();
                  timer.reset();
                }
              : null,
          icon: const Icon(Icons.restart_alt),
        ),
        const SizedBox(width: 24),
        _PlayButton(
          running: timer.isRunning,
          onPressed: () {
            HapticFeedback.mediumImpact();
            timer.toggle();
          },
        ),
        const SizedBox(width: 24),
        onBreak
            ? IconButton.filledTonal(
                tooltip: 'Skip break',
                padding: _side,
                onPressed: timer.skipBreak,
                icon: const Icon(Icons.skip_next),
              )
            : IconButton.filledTonal(
                tooltip: 'Finish & log words',
                padding: _side,
                onPressed: timer.isIdle
                    ? null
                    : () {
                        HapticFeedback.mediumImpact();
                        timer.finish();
                      },
                icon: const Icon(Icons.check),
              ),
      ],
    );
  }
}

/// M3 Expressive "large" (96dp) filled icon button. It morphs from a circle
/// to a rounded square while running, as M3 toggle buttons do when selected.
class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.running, required this.onPressed});
  final bool running;
  final VoidCallback onPressed;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.medium,
    value: widget.running ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant _PlayButton old) {
    super.didUpdateWidget(old);
    if (widget.running != old.running) {
      widget.running ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: widget.running ? 'Pause' : 'Start',
      onPressed: widget.onPressed,
      // Primary-action colours, as M3 uses for the FAB.
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        fixedSize: const Size.square(96),
        animationDuration: Motion.medium,
        shape: widget.running
            ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))
            : const CircleBorder(),
      ),
      icon: AnimatedIcon(
        icon: AnimatedIcons.play_pause,
        progress: _c,
        size: 36,
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final today = store.today;
    final words = store.wordsOn(today);
    final goal = store.goalFor(today);
    final secs = store.secondsOn(today);
    final streak = store.currentStreak;
    final remaining = goal - words;

    return Card.filled(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Today', style: t.titleMedium),
                if (streak > 0) ...[
                  const SizedBox(width: 12),
                  Icon(
                    Icons.local_fire_department_outlined,
                    size: 18,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$streak-day streak',
                    style: t.labelLarge?.copyWith(color: cs.primary),
                  ),
                ],
                const Spacer(),
                if (secs > 0)
                  Text(
                    fmtDuration(secs),
                    style: t.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedCount(words, style: t.headlineMedium),
                Text(
                  '  of ${fmtInt(goal)} words',
                  style: t.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => showLogWordsSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Log'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            WarmProgress(value: goal == 0 ? 0 : words / goal),
            const SizedBox(height: 8),
            Text(
              words == 0
                  ? 'A blank page is just a beginning.'
                  : remaining > 0
                  ? '${fmtInt(remaining)} words to go.'
                  : 'Goal met. Anything more is a bonus.',
              style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
