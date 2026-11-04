import 'package:inkwood/data/timer_controller.dart';
import 'package:inkwood/data/writing_store.dart';
import 'package:inkwood/main.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<WritingStore> pumpApp(
  WidgetTester tester, {
  bool sample = false,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final store = WritingStore(prefs);
  if (sample) store.loadSampleData();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(
          create: (_) => TimerController(store, prefs, clock: clock),
        ),
      ],
      child: const InkwoodApp(),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
  return store;
}

Future<void> loadFonts() async {
  for (final (family, files) in [
    ('Literata', ['Literata-Regular', 'Literata-SemiBold']),
    ('Nunito', ['Nunito-Regular', 'Nunito-SemiBold', 'Nunito-Bold']),
    ('MaterialIcons', <String>[]),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    if (files.isNotEmpty) await loader.load();
  }
}

void main() {
  setUpAll(loadFonts);

  testWidgets('all three tabs render, empty and with data', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    for (final sample in [false, true]) {
      await pumpApp(tester, sample: sample);
      expect(find.text('Writing desk'), findsOneWidget);
      expect(find.text('Pomodoro'), findsOneWidget);

      await tester.tap(find.text('Goal'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Word goal'), findsWidgets);
      expect(find.text('words a day'), findsOneWidget);

      await tester.tap(find.text('Stats'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        find.text(sample ? 'Words per day' : 'Your stats grow here'),
        findsOneWidget,
      );

      for (final r in ['Week', 'Year', 'All']) {
        if (!sample) break;
        await tester.tap(find.text(r));
        await tester.pump(const Duration(seconds: 2));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('timer starts, finishes and asks for words', (tester) async {
    var now = DateTime.now();
    final store = await pumpApp(tester, clock: () => now);
    await tester.tap(find.byTooltip('Start'));
    now = now.add(const Duration(minutes: 3));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('22:00'), findsOneWidget);
    await tester.tap(find.byTooltip('Finish & log words'));
    await tester.pumpAndSettle();
    expect(find.text('Nice stretch'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '320');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.totalWords, 320);
    await tester.pumpWidget(const SizedBox());
  });
}
