import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'ui/shell.dart';
import 'ui/user_picker_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AladinApp()));
}

class AladinApp extends StatelessWidget {
  const AladinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aladin',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('sl'),
      supportedLocales: const [Locale('sl'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Gate(),
    );
  }
}

/// Počaka na naložene podatke, nato zahteva izbiro zaposlenega.
class _Gate extends ConsumerWidget {
  const _Gate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    return boot.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Napaka pri nalaganju podatkov:\n$e',
              textAlign: TextAlign.center),
        )),
      ),
      data: (_) {
        final user = ref.watch(currentUserProvider);
        return user == null ? const UserPickerScreen() : const AppShell();
      },
    );
  }
}
