import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/writing_store.dart';
import '../models/models.dart';
import '../util/format.dart';

class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () =>
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final s = store.settings;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(text, style: t.titleSmall?.copyWith(color: cs.primary)),
    );

    Widget minutes(
      String label,
      int value,
      void Function(AppSettings, int) set, {
      int min = 1,
      int max = 120,
      String unit = 'min',
    }) => ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Less',
            onPressed: value > min
                ? () => store.updateSettings((x) => set(x, value - 1))
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 56,
            child: Text(
              '$value $unit',
              textAlign: TextAlign.center,
              style: t.titleMedium,
            ),
          ),
          IconButton(
            tooltip: 'More',
            onPressed: value < max
                ? () => store.updateSettings((x) => set(x, value + 1))
                : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          header('Pomodoro'),
          minutes('Focus', s.pomodoroFocus, (x, v) => x.pomodoroFocus = v),
          minutes(
            'Short break',
            s.pomodoroShort,
            (x, v) => x.pomodoroShort = v,
          ),
          minutes('Long break', s.pomodoroLong, (x, v) => x.pomodoroLong = v),
          minutes(
            'Rounds before long break',
            s.pomodoroRounds,
            (x, v) => x.pomodoroRounds = v,
            min: 2,
            max: 8,
            unit: '',
          ),
          header('Other timers'),
          minutes('Deep focus', s.deepFocus, (x, v) => x.deepFocus = v),
          minutes('Deep focus break', s.deepBreak, (x, v) => x.deepBreak = v),
          minutes('Sprint', s.sprint, (x, v) => x.sprint = v),
          minutes(
            'Countdown',
            s.countdown,
            (x, v) => x.countdown = v,
            max: 240,
          ),
          SwitchListTile(
            title: const Text('Start breaks automatically'),
            subtitle: const Text('Right after you log a session'),
            value: s.autoStartBreaks,
            onChanged: (v) =>
                store.updateSettings((x) => x.autoStartBreaks = v),
          ),
          SwitchListTile(
            title: const Text('Keep screen on while timing'),
            value: s.keepScreenOn,
            onChanged: (v) => store.updateSettings((x) => x.keepScreenOn = v),
          ),
          header('Notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Timer notifications'),
            subtitle: const Text(
              'A live countdown while timing, and an alert when time\'s up',
            ),
            value: s.notifications,
            onChanged: (v) => store.updateSettings((x) => x.notifications = v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.music_note_outlined),
            title: const Text('Chime when a timer ends'),
            subtitle: const Text('A soft wooden chime instead of silence'),
            value: s.chime,
            onChanged: s.notifications
                ? (v) => store.updateSettings((x) => x.chime = v)
                : null,
          ),
          header('Your data'),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('Copy backup'),
            subtitle: Text(
              '${fmtInt(store.sessions.length)} sessions · paste it somewhere safe',
            ),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: store.exportJson()));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup copied to clipboard')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_go_outlined),
            title: const Text('Restore from clipboard'),
            subtitle: const Text('Replaces everything with a copied backup'),
            onTap: () => _restore(context, store),
          ),
          if (store.sessions.isEmpty)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Load sample data'),
              subtitle: const Text('Ten weeks of pretend writing to explore'),
              onTap: () {
                store.loadSampleData();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: cs.error),
            title: Text(
              'Erase all writing data',
              style: TextStyle(color: cs.error),
            ),
            subtitle: const Text('Sessions, marks and history. Settings stay.'),
            onTap: () => _erase(context, store),
          ),
          header('About'),
          ListTile(
            leading: const Icon(Icons.forest_outlined),
            title: const Text('Inkwood'),
            subtitle: const Text(
              'A quiet cabin for your words. Fonts: Literata & Nunito (SIL OFL).',
            ),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Inkwood'),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, WritingStore store) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final text = data?.text;
    if (text == null || text.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text('This replaces all current data in the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final before = store.snapshot();
    try {
      store.importJson(text);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Backup restored'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => store.restore(before),
          ),
        ),
      );
    } on FormatException {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That doesn\'t look like an Inkwood backup'),
        ),
      );
    }
  }

  Future<void> _erase(BuildContext context, WritingStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase everything?'),
        content: const Text(
          'All sessions, marks and history will be removed. '
          'Copy a backup first if you might want them back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final before = store.snapshot();
    store.eraseAll();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('All writing data erased'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => store.restore(before),
        ),
      ),
    );
  }
}
