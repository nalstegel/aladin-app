import 'package:aladin/data/providers.dart';
import 'package:aladin/data/seed.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/ui/more/more_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Meni Več: Statistika in promet je samo za administratorja.
void main() {
  late ProviderContainer container;

  setUp(() async {
    final store = InMemoryStore();
    await store.save(buildSeedState());
    container = ProviderContainer(
      overrides: [storeProvider.overrideWithValue(store)],
    );
    await container.read(repositoryProvider.notifier).init();
  });

  tearDown(() => container.dispose());

  Future<void> pumpMore(WidgetTester tester, String userId) async {
    container.read(repositoryProvider.notifier).setCurrentUser(userId);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MoreScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('admin vidi Statistika in promet', (tester) async {
    await pumpMore(tester, 'u-nal');

    expect(find.text('Statistika in promet'), findsOneWidget);
  });

  testWidgets('zaposleni ne vidi Statistika in promet', (tester) async {
    await pumpMore(tester, 'u-marko');

    expect(find.text('Statistika in promet'), findsNothing);
    // Ostali vrstici v skupini Poslovno ostaneta.
    expect(find.text('Mere in cena'), findsOneWidget);
    expect(find.text('Cenik'), findsOneWidget);
  });

  testWidgets('vrstica se skrije, ko se prijavi zaposleni', (tester) async {
    await pumpMore(tester, 'u-nal');
    expect(find.text('Statistika in promet'), findsOneWidget);

    container.read(repositoryProvider.notifier).setCurrentUser('u-marko');
    await tester.pump();

    expect(find.text('Statistika in promet'), findsNothing);
  });
}
