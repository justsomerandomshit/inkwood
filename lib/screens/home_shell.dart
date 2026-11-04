import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/timer_controller.dart';
import '../theme/app_theme.dart';
import '../widgets/log_words_sheet.dart';
import 'analytics_screen.dart';
import 'heatmap_screen.dart';
import 'timer_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _sheetOpen = false;
  late final TimerController _timer = context.read<TimerController>();

  @override
  void initState() {
    super.initState();
    _timer.addListener(_onTimer);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTimer());
  }

  @override
  void dispose() {
    _timer.removeListener(_onTimer);
    super.dispose();
  }

  /// When a focus stretch ends (on any tab), ask for the word count.
  Future<void> _onTimer() async {
    final pending = _timer.pendingLog;
    if (pending == null || _sheetOpen || !mounted) return;
    _sheetOpen = true;
    if (_index != 0) setState(() => _index = 0);
    await showLogWordsSheet(
      context,
      start: pending.start,
      seconds: pending.seconds,
      kind: pending.kind,
      completed: pending.completed,
    );
    _sheetOpen = false;
    _timer.consumePendingLog();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const TimerScreen(),
      const HeatmapScreen(),
      AnalyticsScreen(onStartSession: () => setState(() => _index = 0)),
    ];
    return Scaffold(
      body: PageTransitionSwitcher(
        transitionBuilder: (child, primary, secondary) => FadeThroughTransition(
          animation: primary,
          secondaryAnimation: secondary,
          fillColor: Theme.of(context).colorScheme.surface,
          child: child,
        ),
        child: KeyedSubtree(key: ValueKey(_index), child: pages[_index]),
      ),
      floatingActionButton: AnimatedScale(
        scale: _index == 0 ? 0 : 1,
        duration: Motion.of(context, Motion.medium),
        curve: Motion.enter,
        child: FloatingActionButton.extended(
          heroTag: 'log',
          onPressed: _index == 0 ? null : () => showLogWordsSheet(context),
          icon: const Icon(Icons.edit_note),
          label: const Text('Log words'),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Write',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Goal',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Stats',
          ),
        ],
      ),
    );
  }
}
