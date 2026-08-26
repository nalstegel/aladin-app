import 'package:aladin/data/repository.dart';
import 'package:aladin/data/store.dart';
import 'package:aladin/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Povezovanje Firebase računa z zapisom o zaposlenem.
void main() {
  late Repository repo;

  setUp(() async {
    repo = Repository(InMemoryStore());
    await repo.init();
  });

  test('nov račun je vedno delavec, tudi prvi', () {
    // Vloge si nihče ne sme dodeliti sam: če bi si aplikacija smela
    // nastaviti 'admin', bi si jo s podtaknjenim odjemalcem lahko
    // kdorkoli, in dobil pravico pobrisati bazo. Prvega skrbnika ročno
    // nastavi vodja v Firestore konzoli.
    expect(repo.state.users.any((u) => u.hasAccount), isFalse);

    repo.bindAuthUser(uid: 'uid-nal', email: 'nal@aladin.si');
    repo.bindAuthUser(uid: 'uid-marko', email: 'marko@aladin.si');

    expect(repo.state.user('uid-nal')!.role, UserRole.worker);
    expect(repo.state.user('uid-marko')!.role, UserRole.worker);
    expect(repo.state.currentUserId, 'uid-marko');
  });

  test('skrbnik lahko delavcu spremeni vlogo in dostop', () {
    repo.bindAuthUser(uid: 'uid-marko', email: 'marko@aladin.si');
    final marko = repo.state.user('uid-marko')!;

    repo.upsertUser(marko.copyWith(role: UserRole.admin, active: false));

    final updated = repo.state.user('uid-marko')!;
    expect(updated.role, UserRole.admin);
    expect(updated.active, isFalse);
    // Zgodovina mora ostati vezana nanj, zato zaposlenega ne brišemo.
    expect(repo.state.users.where((u) => u.id == 'uid-marko').length, 1);
  });

  test('vnovična prijava ne povozi vloge, ki jo je dodelil skrbnik', () {
    repo.bindAuthUser(uid: 'uid-marko', email: 'marko@aladin.si');
    repo.upsertUser(
      repo.state.user('uid-marko')!.copyWith(role: UserRole.admin),
    );

    repo.bindAuthUser(uid: 'uid-marko', email: 'marko@aladin.si');

    expect(repo.state.user('uid-marko')!.role, UserRole.admin);
  });

  test('ponovna prijava istega računa ne podvoji zaposlenega', () {
    repo.bindAuthUser(uid: 'uid-nal', email: 'nal@aladin.si');
    final countAfterFirst = repo.state.users.length;

    repo.bindAuthUser(uid: 'uid-nal', email: 'nal@aladin.si');

    expect(repo.state.users.length, countAfterFirst);
    expect(repo.state.currentUserId, 'uid-nal');
  });

  test('ime se izpelje iz e-naslova, dokler si ga ne popravi sam', () {
    repo.bindAuthUser(uid: 'uid-mn', email: 'marko.novak@aladin.si');

    expect(repo.state.user('uid-mn')!.name, 'Marko Novak');
  });

  test('zgodovina kosa se pripiše prijavljenemu računu', () {
    repo.bindAuthUser(uid: 'uid-nal', email: 'nal@aladin.si');
    final order = repo.createOrder(
      customer: repo.state.customers.first,
      channel: OrderChannel.dropoff,
      handover: HandoverMode.customerCollects,
      itemCount: 1,
    );

    final event = repo.state.item('${order.id}-1')!.history.first;
    expect(event.userId, 'uid-nal');
  });

  test('odjava počisti prijavljenega zaposlenega', () {
    repo.bindAuthUser(uid: 'uid-nal', email: 'nal@aladin.si');
    expect(repo.state.currentUserId, isNotNull);

    repo.clearCurrentUser();

    expect(repo.state.currentUserId, isNull);
    expect(repo.state.currentUser, isNull);
  });
}
