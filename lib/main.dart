import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/auth.dart';
import 'data/providers.dart';
import 'firebase_options.dart';
import 'ui/login_screen.dart';
import 'ui/shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
      home: const _AuthGate(),
    );
  }
}

const _loading = Scaffold(body: Center(child: CircularProgressIndicator()));

Widget _errorScreen(String message) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center),
        ),
      ),
    );

/// Brez prijave ni dostopa do podatkov. Firebase sejo hrani sam, zato se
/// zaposleni prijavi enkrat na telefon in ostane prijavljen.
class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authStateProvider).when(
          loading: () => _loading,
          error: (e, _) => _errorScreen('Napaka pri preverjanju prijave:\n$e'),
          data: (user) =>
              user == null ? const LoginScreen() : _DataGate(authUser: user),
        );
  }
}

/// Naloži podatke in poveže prijavljeni račun z zapisom o zaposlenem.
class _DataGate extends ConsumerStatefulWidget {
  const _DataGate({required this.authUser});

  final User authUser;

  @override
  ConsumerState<_DataGate> createState() => _DataGateState();
}

class _DataGateState extends ConsumerState<_DataGate> {
  @override
  void initState() {
    super.initState();
    _bind();
  }

  Future<void> _bind() async {
    // Šele ko so podatki naloženi, lahko preverimo, ali zaposleni že
    // obstaja, in mu po potrebi ustvarimo zapis.
    await ref.read(bootstrapProvider.future);
    if (!mounted) return;
    ref.read(repositoryProvider.notifier).bindAuthUser(
          uid: widget.authUser.uid,
          email: widget.authUser.email ?? '',
          displayName: widget.authUser.displayName,
        );
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(bootstrapProvider).when(
          loading: () => _loading,
          error: (e, _) => _errorScreen('Napaka pri nalaganju podatkov:\n$e'),
          // Med prvim zagonom počakamo, da se račun poveže z zaposlenim,
          // sicer bi se prvi skeni pripisali "neznanemu uporabniku".
          data: (_) => ref.watch(currentUserProvider) == null
              ? _loading
              : const AppShell(),
        );
  }
}
