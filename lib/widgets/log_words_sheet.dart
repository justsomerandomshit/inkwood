import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/writing_store.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../util/format.dart';

/// Opens the sheet to record words. Use [start]/[seconds]/[kind] after a timer
/// session, [day] to log manually for a given date, or [editing] to amend an
/// existing session. Returns true when something was saved.
Future<bool> showLogWordsSheet(
  BuildContext context, {
  DateTime? start,
  int? seconds,
  TimerKind kind = TimerKind.manual,
  DateTime? day,
  WritingSession? editing,
  bool completed = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final store = context.read<WritingStore>();
  final goalBefore = store.goalMetOn(store.today);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _LogWordsSheet(
      start: start,
      seconds: seconds,
      kind: editing?.kind ?? kind,
      day: day,
      editing: editing,
      completed: completed,
    ),
  );
  if (saved == true && !goalBefore && store.goalMetOn(store.today)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Daily goal reached — ${fmtInt(store.wordsOn(store.today))} words today.',
        ),
      ),
    );
  }
  return saved == true;
}

class _LogWordsSheet extends StatefulWidget {
  const _LogWordsSheet({
    required this.start,
    required this.seconds,
    required this.kind,
    required this.day,
    required this.editing,
    required this.completed,
  });

  final DateTime? start;
  final int? seconds;
  final TimerKind kind;
  final DateTime? day;
  final WritingSession? editing;
  final bool completed;

  @override
  State<_LogWordsSheet> createState() => _LogWordsSheetState();
}

enum _Mode { words, total }

class _LogWordsSheetState extends State<_LogWordsSheet> {
  late final WritingStore store = context.read<WritingStore>();
  late final _words = TextEditingController(
    text: widget.editing != null ? '${widget.editing!.words}' : '',
  );
  late final _from = TextEditingController(
    text: store.lastManuscriptTotal?.toString() ?? '',
  );
  final _to = TextEditingController();
  late final _minutes = TextEditingController(
    text: widget.editing != null && widget.editing!.durationSec > 0
        ? '${(widget.editing!.durationSec / 60).round()}'
        : '',
  );
  late final _note = TextEditingController(text: widget.editing?.note ?? '');
  _Mode _mode = _Mode.words;
  late DateTime _date =
      widget.editing?.start ?? widget.start ?? widget.day ?? DateTime.now();

  bool get _fromTimer => widget.seconds != null && widget.editing == null;
  bool get _isManual => widget.kind == TimerKind.manual;

  int get _wordCount {
    if (_mode == _Mode.words) return int.tryParse(_words.text) ?? 0;
    final a = int.tryParse(_from.text);
    final b = int.tryParse(_to.text);
    if (a == null || b == null) return 0;
    return (b - a).clamp(0, 1 << 30);
  }

  int get _seconds {
    if (_fromTimer) return widget.seconds!;
    final m = int.tryParse(_minutes.text);
    if (m != null) return m * 60;
    return widget.editing?.durationSec ?? 0;
  }

  bool get _canSave => _fromTimer || _wordCount > 0 || _seconds > 0;

  @override
  void dispose() {
    for (final c in [_words, _from, _to, _minutes, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addWords(int n) {
    HapticFeedback.selectionClick();
    final v = (int.tryParse(_words.text) ?? 0) + n;
    setState(() => _words.text = '$v');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(
        () => _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        ),
      );
    }
  }

  void _save() {
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    if (_mode == _Mode.total) {
      store.setManuscriptTotal(int.tryParse(_to.text));
    }
    final editing = widget.editing;
    if (editing != null) {
      store.updateSession(
        editing.copyWith(
          start: _date,
          words: _wordCount,
          durationSec: _seconds,
          note: note ?? '',
        ),
      );
    } else {
      // A manual entry for a past day lands at noon, so it can't drift days.
      final start = _isManual && !sameDay(_date, DateTime.now())
          ? DateTime(_date.year, _date.month, _date.day, 12)
          : (widget.start ?? _date);
      store.addSession(
        start: start,
        durationSec: _seconds,
        words: _wordCount,
        kind: widget.kind,
        note: note,
      );
    }
    HapticFeedback.mediumImpact();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final title = widget.editing != null
        ? 'Edit session'
        : _fromTimer
        ? (widget.completed ? 'Session complete' : 'Nice stretch')
        : 'Log words';
    final subtitle = _fromTimer
        ? '${widget.kind.label} · ${fmtDuration(widget.seconds!)} of focus. How many words did you write?'
        : 'Record writing you did, here or away from the app.';

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: t.headlineSmall),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SegmentedButton<_Mode>(
              segments: const [
                ButtonSegment(
                  value: _Mode.words,
                  label: Text('Words written'),
                  icon: Icon(Icons.edit_outlined),
                ),
                ButtonSegment(
                  value: _Mode.total,
                  label: Text('From total'),
                  icon: Icon(Icons.menu_book_outlined),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            AnimatedSize(
              duration: Motion.of(context, Motion.medium),
              curve: Motion.enter,
              alignment: Alignment.topCenter,
              child: _mode == _Mode.words
                  ? _wordsInput(t, cs)
                  : _totalInput(t, cs),
            ),
            if (!_fromTimer) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      readOnly: true,
                      enabled: _isManual,
                      onTap: _pickDate,
                      controller: TextEditingController(
                        text: DateFormat.yMMMd().format(_date),
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        suffixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Minutes',
                        hintText: 'Optional',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Chapter 3, the storm scene…',
                prefixIcon: Icon(Icons.sticky_note_2_outlined),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                if (_fromTimer)
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Discard'),
                  ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _canSave ? _save : null,
                  icon: const Icon(Icons.check),
                  label: Text(
                    _fromTimer && _wordCount == 0 ? 'Save time only' : 'Save',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wordsInput(TextTheme t, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _words,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: t.displaySmall,
          textAlign: TextAlign.center,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: '0',
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            hintStyle: t.displaySmall?.copyWith(color: cs.onSurfaceVariant),
            suffixText: 'words',
            suffixStyle: t.titleMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final n in [50, 100, 250, 500])
              ActionChip(label: Text('+$n'), onPressed: () => _addWords(n)),
          ],
        ),
      ],
    );
  }

  Widget _totalInput(TextTheme t, ColorScheme cs) {
    final diff = _wordCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _from,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Started at'),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward),
            ),
            Expanded(
              child: TextField(
                controller: _to,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Now at'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          diff > 0 ? '+${fmtInt(diff)} words this session' : 'Enter your manuscript\'s word count before and after. We\'ll remember the new total for next time.',
          textAlign: TextAlign.center,
          style: diff > 0
              ? t.titleMedium?.copyWith(color: cs.primary)
              : t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}
