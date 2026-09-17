import 'dart:async';

import 'package:aladin/data/app_state.dart';
import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/customer.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shramba, ki zna oddajati spremembe "z drugega telefona", da lahko
/// preverimo sinhronizacijo brez pravega Firestora.
class _FakeSyncStore implements DataStore {
  AppState? _saved;
  final _controller = StreamController<AppState>.broadcast();

  /// Koliko zapisov v bazo se je zgodilo — prejeta sprememba z drugega
  /// telefona ne sme sprožiti novega zapisa.
  int saveCount = 0;

  @override
  Future<AppState?> load() async => _saved;

  @override
  Future<void> save(AppState state) async {
    saveCount++;
    _saved = state;
  }

  @override
  Future<void> clear() async => _saved = null;

  @override
  Stream<AppState> watch() => _controller.stream;

  /// Simulira posnetek, kot ga pošlje Firestore: brez `currentUserId`,
  /// ker je ta stvar posamezne naprave.
  void pushRemote(AppState state) => _controller.add(state);

  Future<void> dispose() => _controller.close();
}

/// Ustvari stanje, kakršno pride iz Firestora — torej brez `currentUserId`.
AppState _asRemote(AppState s, {List<Customer>? customers}) => AppState(
      customers: customers ?? s.customers,
      orders: s.orders,
      items: s.items,
      rugTypes: s.rugTypes,
      extraTemplates: s.extraTemplates,
      users: s.users,
      nextOrderSeqLjubljana: s.nextOrderSeqLjubljana,
      nextOrderSeqMaribor: s.nextOrderSeqMaribor,
    );

void main() {
  late _FakeSyncStore store;
  late Repository repo;

  setUp(() async {
    store = _FakeSyncStore();
    repo = Repository(store);
    await repo.init();
    repo.setCurrentUser('u-marko');
  });

  tearDown(() async {
    repo.dispose();
    await store.dispose();
  });

  test('sprememba z drugega telefona se pokaže brez ponovnega zagona',
      () async {
    expect(repo.state.customer('c-nova'), isNull);

    store.pushRemote(_asRemote(
      repo.state,
      customers: [
        ...repo.state.customers,
        Customer(
          id: 'c-nova',
          type: CustomerType.private,
          name: 'Nova Stranka',
          createdAt: DateTime.now(),
        ),
      ],
    ));
    await Future<void>.delayed(Duration.zero);

    expect(repo.state.customer('c-nova')?.name, 'Nova Stranka');
  });

  test('prejeta sprememba ohrani zaposlenega, prijavljenega na tem telefonu',
      () async {
    expect(repo.state.currentUserId, 'u-marko');

    // Firestore nikoli ne pošlje currentUserId — če ga Repository ne bi
    // ohranil, bi zaposlenega vrglo nazaj na izbirni zaslon.
    store.pushRemote(_asRemote(repo.state));
    await Future<void>.delayed(Duration.zero);

    expect(repo.state.currentUserId, 'u-marko');
  });

  test('prejeta sprememba ne sproži novega zapisa v bazo', () async {
    final before = store.saveCount;

    store.pushRemote(_asRemote(repo.state));
    await Future<void>.delayed(Duration.zero);

    // Zapis nazaj bi pomenil, da si telefoni brez konca podajajo posnetke.
    expect(store.saveCount, before);
  });
}
