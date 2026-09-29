import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'controller.dart';
import 'shell.dart';
import 'storage.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Nunito',
    ], await rootBundle.loadString('assets/fonts/OFL.txt'));
    for (final entry in {
      'Embedded Russian speech': 'assets/voice/NOTICE.md',
      'Sherpa-ONNX': 'assets/voice/SHERPA_LICENSE',
      'Vosk Small Russian': 'assets/voice/asr/LICENSE',
      'eSpeak NG': 'assets/voice/ESPEAK_LICENSE',
      'Three.js': 'assets/game3d/vendor/THREE-LICENSE.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: cream,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const KopilychApp());
}

class KopilychApp extends StatefulWidget {
  const KopilychApp({super.key, this.store});
  final GameStore? store;
  @override
  State<KopilychApp> createState() => _KopilychAppState();
}

class _KopilychAppState extends State<KopilychApp> {
  GameController? controller;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    open();
  }

  Future<void> open() async {
    setState(() => failed = false);
    try {
      final store = widget.store ?? await GameStore.open();
      final c = GameController(store);
      await c.load();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => controller = c);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Копилыч',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(),
    home: controller == null
        ? Scaffold(
            body: Center(
              child: failed
                  ? Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Не удалось открыть сохранение. Данные не удалены.',
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: open,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    )
                  : const CircularProgressIndicator(),
            ),
          )
        : GameShell(controller: controller!),
  );
}
