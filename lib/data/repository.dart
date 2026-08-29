import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/app_user.dart';
import '../models/catalog.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../models/return_proof.dart';
import '../models/rug_item.dart';
import '../models/status_event.dart';
import 'app_state.dart';
import 'seed.dart';
import 'store.dart';

const _uuid = Uuid();

/// Vsa poslovna logika sistema. UI kliče samo metode tega razreda.
class Repository extends StateNotifier<AppState> {
  Repository(this._store) : super(const AppState());

  final DataStore _store;
  bool _loaded = false;
  StreamSubscription<AppState>? _remoteSub;

  bool get isLoaded => _loaded;

  Future<void> init() async {
    final saved = await _store.load();
    state = saved ?? buildSeedState();
    _loaded = true;
    if (saved == null) await _store.save(state);

    // Spremembe z drugih telefonov sprejmemo takoj, brez ponovnega zagona.
    // Namenoma NE kličemo _commit — sicer bi vsak prejet posnetek sprožil
    // nov zapis nazaj v bazo in bi se telefoni vrteli v krogu.
    _remoteSub = _store.watch().listen(
      (remote) {
        if (!mounted) return;
        // Kdo dela na TEM telefonu, ostane lokalna izbira te naprave.
        state = remote.copyWith(currentUserId: state.currentUserId);
      },
      // Po odjavi pravila zavrnejo branje in poslušalci javijo napako.
      // To je pričakovano — aplikacija je takrat že na prijavnem zaslonu.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _remoteSub?.cancel();
    super.dispose();
  }

  void _commit(AppState next) {
    state = next;
    _store.save(next);
  }

  AppUser get _actor =>
      state.currentUser ??
      const AppUser(id: 'unknown', name: 'Neznan uporabnik');

  // ---------------------------------------------------------------- uporabnik

  void setCurrentUser(String userId) =>
      _commit(state.copyWith(currentUserId: userId));

  /// Poveže prijavljeni Firebase račun z zapisom o zaposlenem.
  ///
  /// Zapis o zaposlenem je ključen z Auth UID-jem, zato je zgodovina
  /// ("kdo je skeniral ta kos") vezana na pravi račun in ne več na ime,
  /// ki si ga je kdorkoli lahko izbral s seznama.
  ///
  /// Nov zaposleni je VEDNO delavec. Vloge si nihče ne sme dodeliti sam —
  /// `firestore.rules` tak zapis zavrne, ker bi si sicer lahko kdorkoli
  /// nastavil 'admin' in dobil pravico pobrisati bazo. Prvega skrbnika
  /// ročno nastavi vodja v Firestore konzoli, nato vloge ostalim ureja v
  /// aplikaciji (Nastavitve → Zaposleni).
  void bindAuthUser({
    required String uid,
    required String email,
    String? displayName,
  }) {
    final existing = state.user(uid);

    if (existing != null) {
      if (existing.email == email) {
        _commit(state.copyWith(currentUserId: uid));
        return;
      }
      final users = [...state.users];
      users[users.indexWhere((u) => u.id == uid)] =
          existing.copyWith(email: email);
      _commit(state.copyWith(users: users, currentUserId: uid));
      return;
    }

    final user = AppUser(
      id: uid,
      name: displayName == null || displayName.trim().isEmpty
          ? _nameFromEmail(email)
          : displayName.trim(),
      email: email,
      role: UserRole.worker,
    );
    _commit(state.copyWith(
      users: [...state.users, user],
      currentUserId: uid,
    ));
  }

  /// Ob odjavi — dejansko odjavo opravi [AuthService].
  void clearCurrentUser() => _commit(state.copyWith(clearCurrentUser: true));

  /// "marko.novak@..." → "Marko Novak", dokler si imena ne popravi sam.
  static String _nameFromEmail(String email) {
    final local = email.split('@').first.replaceAll(RegExp(r'[._\-]+'), ' ');
    final words = local.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return 'Zaposleni';
    return words
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  void upsertUser(AppUser user) {
    final list = [...state.users];
    final i = list.indexWhere((u) => u.id == user.id);
    if (i >= 0) {
      list[i] = user;
    } else {
      list.add(user);
    }
    _commit(state.copyWith(users: list));
  }

  AppUser createUser(String name, UserRole role) {
    final user = AppUser(id: _uuid.v4(), name: name, role: role);
    upsertUser(user);
    return user;
  }

  // ----------------------------------------------------------------- stranke

  Customer createCustomer({
    required CustomerType type,
    required String name,
    String phone = '',
    String email = '',
    String address = '',
    String city = '',
    String postalCode = '',
    String taxId = '',
    String contactPerson = '',
    double defaultDiscountPercent = 0,
    String notes = '',
  }) {
    final c = Customer(
      id: _uuid.v4(),
      type: type,
      name: name.trim(),
      phone: phone.trim(),
      email: email.trim(),
      address: address.trim(),
      city: city.trim(),
      postalCode: postalCode.trim(),
      taxId: taxId.trim(),
      contactPerson: contactPerson.trim(),
      defaultDiscountPercent: defaultDiscountPercent,
      notes: notes.trim(),
      createdAt: DateTime.now(),
    );
    _commit(state.copyWith(customers: [...state.customers, c]));
    return c;
  }

  void updateCustomer(Customer customer) {
    final list = [...state.customers];
    final i = list.indexWhere((c) => c.id == customer.id);
    if (i < 0) return;
    list[i] = customer;

    // Podvojene podatke na naročilih držimo usklajene.
    final orders = state.orders
        .map((o) => o.customerId == customer.id
            ? o.copyWith(
                customerName: customer.name,
                customerPhone: customer.phone,
                customerAddress: customer.fullAddress,
              )
            : o)
        .toList();
    _commit(state.copyWith(customers: list, orders: orders));
  }

  // ---------------------------------------------------------------- naročila

  /// Ustvari naročilo in zanj takoj generira vse kose z QR ID-ji.
  WorkOrder createOrder({
    required Customer customer,
    required OrderChannel channel,
    required HandoverMode handover,
    required int itemCount,
    DateTime? pickupAt,
    DateTime? deliveryAt,
    DateTime? dueAt,
    String notes = '',
    List<String> conditions = const [],
  }) {
    final number = state.nextOrderNumber;
    final id = '$number';
    final now = DateTime.now();

    // Pri dostavi preprog še nimamo v obratu — čakajo na prevzem.
    final startStatus = channel == OrderChannel.delivery && pickupAt != null
        ? RugStatus.awaitingPickup
        : RugStatus.awaitingWash;

    final order = WorkOrder(
      id: id,
      channel: channel,
      handover: handover,
      status: startStatus == RugStatus.awaitingPickup
          ? OrderStatus.scheduledPickup
          : OrderStatus.inProduction,
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerAddress: customer.fullAddress,
      itemCount: itemCount,
      pickupAt: pickupAt,
      deliveryAt: deliveryAt,
      dueAt: dueAt,
      notes: notes.trim(),
      createdAt: now,
      createdByName: _actor.name,
    );

    final items = <RugItem>[
      for (var n = 1; n <= itemCount; n++)
        RugItem(
          id: '$id-$n',
          orderId: id,
          index: n,
          ofTotal: itemCount,
          status: startStatus,
          condition: n <= conditions.length ? conditions[n - 1] : '',
          history: [
            StatusEvent(
              status: startStatus,
              at: now,
              userId: _actor.id,
              userName: _actor.name,
              note: 'Naročilo ustvarjeno',
            ),
          ],
        ),
    ];

    _commit(state.copyWith(
      orders: [...state.orders, order],
      items: [...state.items, ...items],
      nextOrderNumber: number + 1,
    ));
    return order;
  }

  void updateOrder(WorkOrder order) {
    final list = [...state.orders];
    final i = list.indexWhere((o) => o.id == order.id);
    if (i < 0) return;
    list[i] = order;
    _commit(state.copyWith(orders: list));
  }

  /// Dodaj kos obstoječemu naročilu (stranka je prinesla še eno preprogo).
  RugItem addItemToOrder(String orderId) {
    final order = state.order(orderId);
    if (order == null) throw StateError('Naročilo $orderId ne obstaja');
    final existing = state.itemsOf(orderId);
    final total = existing.length + 1;
    final now = DateTime.now();

    final renumbered =
        existing.map((i) => i.copyWith(ofTotal: total)).toList();
    final fresh = RugItem(
      id: '$orderId-$total',
      orderId: orderId,
      index: total,
      ofTotal: total,
      status: RugStatus.awaitingWash,
      history: [
        StatusEvent(
          status: RugStatus.awaitingWash,
          at: now,
          userId: _actor.id,
          userName: _actor.name,
          note: 'Kos dodan naknadno',
        ),
      ],
    );

    final items = [
      ...state.items.where((i) => i.orderId != orderId),
      ...renumbered,
      fresh,
    ];
    final orders = [...state.orders];
    final oi = orders.indexWhere((o) => o.id == orderId);
    orders[oi] = order.copyWith(itemCount: total);

    _commit(_recompute(
      state.copyWith(items: items, orders: orders),
      orderId,
    ));
    return fresh;
  }

  /// Preproge smo pobrali pri stranki — vse čakajo na pranje.
  void markOrderPickedUp(String orderId) {
    final now = DateTime.now();
    final items = state.items.map((i) {
      if (i.orderId != orderId || i.status != RugStatus.awaitingPickup) return i;
      return i.copyWith(
        status: RugStatus.awaitingWash,
        history: [..._event(i, RugStatus.awaitingWash, now, 'Prevzeto pri stranki')],
      );
    }).toList();
    _commit(_recompute(state.copyWith(items: items), orderId));
  }

  // ---------------------------------------------------------------- preproge

  List<StatusEvent> _event(
    RugItem item,
    RugStatus status,
    DateTime at,
    String note,
  ) =>
      [
        ...item.history,
        StatusEvent(
          status: status,
          at: at,
          userId: _actor.id,
          userName: _actor.name,
          note: note,
        ),
      ];

  void _saveItem(RugItem updated) {
    final items = [...state.items];
    final i = items.indexWhere((e) => e.id == updated.id);
    if (i < 0) return;
    items[i] = updated;
    _commit(_recompute(state.copyWith(items: items), updated.orderId));
  }

  /// Kaj se zgodi ob skeniranju: naslednji korak v proizvodnji.
  ///
  /// Vrne nov status ali null, če koraka ni mogoče izvesti samodejno
  /// (npr. potrebni so mere ali potrditev cene).
  RugStatus? nextStatusFor(RugItem item) => switch (item.status) {
        RugStatus.awaitingPickup => RugStatus.awaitingWash,
        RugStatus.awaitingWash => RugStatus.drying,
        // Naslednja koraka zahtevata vnos — obravnava ju UI.
        RugStatus.drying => null,
        RugStatus.finishing => null,
        RugStatus.ready => null,
        RugStatus.returned => null,
      };

  /// Premakne kos za en korak naprej, kadar vnos ni potreben.
  bool advance(String itemId, {String note = ''}) {
    final item = state.item(itemId);
    if (item == null) return false;
    final next = nextStatusFor(item);
    if (next == null) return false;
    _saveItem(item.copyWith(
      status: next,
      history: _event(item, next, DateTime.now(), note),
    ));
    return true;
  }

  /// Korak "iz sušilnice": mere + vrsta → izračun m² in osnovne cene.
  void setMeasurements(
    String itemId, {
    double? widthCm,
    double? lengthCm,
    double? manualM2,
    required RugType rugType,
    String notes = '',
  }) {
    final item = state.item(itemId);
    if (item == null) return;
    final updated = item.copyWith(
      status: RugStatus.finishing,
      widthCm: widthCm,
      lengthCm: lengthCm,
      manualM2: manualM2,
      clearManualM2: manualM2 == null,
      rugTypeId: rugType.id,
      rugTypeName: rugType.name,
      pricePerM2: rugType.pricePerM2,
      minChargeM2: rugType.minChargeM2,
      notes: notes,
      history: _event(
        item,
        RugStatus.finishing,
        DateTime.now(),
        'Mere in vrsta vnesene',
      ),
    );
    _saveItem(updated);
  }

  /// Končno sesanje: doplačila, popust, potrditev cene → Pripravljeno.
  void finishItem(
    String itemId, {
    required List<AppliedExtra> extras,
    required double discountPercent,
    double? priceOverride,
    String notes = '',
  }) {
    final item = state.item(itemId);
    if (item == null) return;
    final withPricing = item.copyWith(
      extras: extras,
      discountPercent: discountPercent,
      notes: notes,
    );
    final finalPrice = priceOverride ?? withPricing.computedPrice;
    _saveItem(withPricing.copyWith(
      status: RugStatus.ready,
      confirmedPrice: finalPrice,
      history: _event(
        item,
        RugStatus.ready,
        DateTime.now(),
        'Cena potrjena: ${finalPrice.toStringAsFixed(2)} €',
      ),
    ));
  }

  /// Preproga ni bila dovolj čista — nazaj v pranje.
  void sendBackToWash(String itemId, String reason) {
    final item = state.item(itemId);
    if (item == null) return;
    _saveItem(item.copyWith(
      status: RugStatus.awaitingWash,
      clearConfirmedPrice: true,
      history: _event(
        item,
        RugStatus.awaitingWash,
        DateTime.now(),
        reason.isEmpty ? 'Ponovno pranje' : 'Ponovno pranje: $reason',
      ),
    ));
  }

  /// Ročni popravek statusa (napačno skeniranje). Namenjeno administratorju.
  void overrideStatus(String itemId, RugStatus status, String reason) {
    final item = state.item(itemId);
    if (item == null) return;
    _saveItem(item.copyWith(
      status: status,
      history: _event(item, status, DateTime.now(), 'Ročni popravek: $reason'),
    ));
  }

  void updateItemNotes(String itemId, {String? notes, String? condition}) {
    final item = state.item(itemId);
    if (item == null) return;
    _saveItem(item.copyWith(notes: notes, condition: condition));
  }

  // ----------------------------------------------------------------- vračilo

  /// Zaključi naročilo: vsi kosi vrnjeni, dokazilo shranjeno.
  void completeReturn(String orderId, ReturnProof proof) {
    final now = proof.returnedAt;
    final items = state.items.map((i) {
      if (i.orderId != orderId) return i;
      return i.copyWith(
        status: RugStatus.returned,
        history: _event(
          i,
          RugStatus.returned,
          now,
          proof.isOverride
              ? 'Vrnjeno brez podpisa: ${proof.overrideReason}'
              : 'Vrnjeno in podpisano',
        ),
      );
    }).toList();

    final orders = [...state.orders];
    final oi = orders.indexWhere((o) => o.id == orderId);
    if (oi >= 0) {
      orders[oi] = orders[oi].copyWith(
        status: OrderStatus.completed,
        completedAt: now,
        returnProof: proof,
      );
    }
    _commit(state.copyWith(items: items, orders: orders));
  }

  // ------------------------------------------------------------------ cenik

  void upsertRugType(RugType type) {
    final list = [...state.rugTypes];
    final i = list.indexWhere((t) => t.id == type.id);
    if (i >= 0) {
      list[i] = type;
    } else {
      list.add(type);
    }
    _commit(state.copyWith(rugTypes: list));
  }

  RugType createRugType(String name, double pricePerM2, double minChargeM2) {
    final t = RugType(
      id: _uuid.v4(),
      name: name,
      pricePerM2: pricePerM2,
      minChargeM2: minChargeM2,
    );
    upsertRugType(t);
    return t;
  }

  void upsertExtraTemplate(ExtraTemplate template) {
    final list = [...state.extraTemplates];
    final i = list.indexWhere((t) => t.id == template.id);
    if (i >= 0) {
      list[i] = template;
    } else {
      list.add(template);
    }
    _commit(state.copyWith(extraTemplates: list));
  }

  ExtraTemplate createExtraTemplate(String name, ExtraKind kind, double value) {
    final t =
        ExtraTemplate(id: _uuid.v4(), name: name, kind: kind, value: value);
    upsertExtraTemplate(t);
    return t;
  }

  // --------------------------------------------------------------- razvojno

  Future<void> resetToSeed() async {
    await _store.clear();
    _commit(buildSeedState());
  }

  // -------------------------------------------------------------- izpeljava

  /// Status naročila je vedno posledica stanja kosov, nikoli ročno nastavljen.
  AppState _recompute(AppState s, String orderId) {
    final orders = [...s.orders];
    final oi = orders.indexWhere((o) => o.id == orderId);
    if (oi < 0) return s;
    final order = orders[oi];
    if (order.status == OrderStatus.cancelled) return s;

    final items = s.itemsOf(orderId);
    if (items.isEmpty) return s;

    OrderStatus next;
    DateTime? readyAt = order.readyAt;

    if (items.every((i) => i.status == RugStatus.returned)) {
      next = OrderStatus.completed;
    } else if (items.every((i) =>
        i.status == RugStatus.ready || i.status == RugStatus.returned)) {
      next = order.handover == HandoverMode.customerCollects
          ? OrderStatus.awaitingCollection
          : OrderStatus.awaitingDelivery;
      readyAt ??= DateTime.now();
    } else if (items.every((i) => i.status == RugStatus.awaitingPickup)) {
      next = OrderStatus.scheduledPickup;
      readyAt = null;
    } else {
      next = OrderStatus.inProduction;
      readyAt = null;
    }

    if (next == order.status && readyAt == order.readyAt) return s;
    orders[oi] = order.copyWith(
      status: next,
      readyAt: readyAt,
      clearReadyAt: readyAt == null,
    );
    return s.copyWith(orders: orders);
  }
}
