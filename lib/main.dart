import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/notifier.dart';
import 'data/timer_controller.dart';
import 'data/writing_store.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final font in ['Fraunces', 'Nunito']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$font.txt');
      yield LicenseEntryWithLineBreaks([font], text);
    }
  });
  final prefs = await SharedPreferences.getInstance();
  final store = WritingStore(prefs);
  final notifier = TimerNotifier();
  await notifier.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        ChangeNotifierProvider(
          create: (_) => TimerController(store, prefs, notifier: notifier),
        ),
      ],
      child: const InkwoodApp(),
    ),
  );
}

class InkwoodApp extends StatelessWidget {
  const InkwoodApp({super.key});

  static final _theme = buildTheme();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Inkwood',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      darkTheme: _theme,
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
