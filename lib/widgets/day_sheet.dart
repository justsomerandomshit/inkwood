import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/writing_store.dart';
import '../models/models.dart';
import '../util/format.dart';
import 'common.dart';
import 'log_words_sheet.dart';

Future<void> showDaySheet(BuildContext context, DateTime day) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _DaySheet(day: day),
  );
}

enum _MarkChoice { none, done, rest }

class _DaySheet extends StatelessWidget {
  const _DaySheet({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<WritingStore>();
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final words = store.wordsOn(day);
    final goal = store.goalFor(day);
    final mark = store.markOn(day);
    final sessions = store.sessionsOn(day);
    final choice = switch (mark) {
      DayMark.done => _MarkChoice.done,
      DayMark.rest => _MarkChoice.rest,
      null => _MarkChoice.none,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          Text(DateFormat.MMMMEEEEd().format(day), style: t.headlineSmall),
          if (store.isBeforeFreshStart(day))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Before your fresh start — kept for history, not counted.',
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedCount(words, style: t.displaySmall),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'of ${fmtInt(goal)} words',
                  style: t.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const Spacer(),
              if (store.secondsOn(day) > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    fmtDuration(store.secondsOn(day)),
                    style: t.titleMedium,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          WarmProgress(value: goal == 0 ? 0 : words / goal),
          const SizedBox(height: 24),
          Text('Mark this day', style: t.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<_MarkChoice>(
            segments: const [
              ButtonSegment(value: _MarkChoice.none, label: Text('Auto')),
              ButtonSegment(
                value: _MarkChoice.done,
                label: Text('Goal met'),
                icon: Icon(Icons.check_circle_outline),
              ),
              ButtonSegment(
                value: _MarkChoice.rest,
                label: Text('Rest'),
                icon: Icon(Icons.bedtime_outlined),
              ),
            ],
            selected: {choice},
            onSelectionChanged: (s) {
              HapticFeedback.selectionClick();
              store.setMark(day, switch (s.first) {
                _MarkChoice.done => DayMark.done,
                _MarkChoice.rest => DayMark.rest,
                _MarkChoice.none => null,
              });
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Rest days keep your streak intact. "Goal met" counts writing done away from the app.',
            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Sessions', style: t.titleSmall)),
              TextButton.icon(
                onPressed: () => showLogWordsSheet(context, day: day),
                icon: const Icon(Icons.add),
                label: const Text('Log words'),
              ),
            ],
          ),
          if (sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nothing logged yet.',
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          for (final s in sessions) SessionTile(session: s),
        ],
      ),
    );
  }
}

/// A session row with tap-to-edit and swipe-to-delete (with undo).
class SessionTile extends StatelessWidget {
  const SessionTile({super.key, required this.session, this.showDate = false});

  final WritingSession session;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final store = context.read<WritingStore>();
    final s = session;
    final when = showDate
        ? DateFormat.MMMd().add_jm().format(s.start)
        : DateFormat.jm().format(s.start);
    final parts = [
      when,
      if (s.durationSec > 0) fmtDuration(s.durationSec),
      if (s.note != null) s.note!,
    ];
    return Dismissible(
      key: ValueKey(s.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete_outline, color: cs.onErrorContainer),
      ),
      onDismissed: (_) {
        store.removeSession(s.id);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('Removed ${fmtInt(s.words)} words'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => store.insertSession(s),
              ),
            ),
          );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.onPrimaryContainer,
          child: Icon(s.kind.icon, size: 20),
        ),
        title: Text('${fmtInt(s.words)} words'),
        subtitle: Text(
          parts.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right, color: cs.outline),
        onTap: () => showLogWordsSheet(context, editing: s),
      ),
    );
  }
}
