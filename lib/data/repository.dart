import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/order_id.dart';
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
    required OrderLocation location,
    required OrderChannel channel,
    required HandoverMode handover,
    required int itemCount,
    DateTime? pickupAt,
    DateTime? pickupWindowEnd,
    DateTime? deliveryAt,
    DateTime? dueAt,
    double deliveryFee = 0,
    String notes = '',
    List<String> conditions = const [],
  }) {
    final seq = state.nextOrderSeq(location);
    final id = buildOrderId(location, seq);
    final now = DateTime.now();

    // Vsako novo naročilo začne v zavihku "Naročila": v "Čaka pranje" gre
    // šele s potrditvijo fizičnega prevzema (V8 §2) — tudi Pripeljano. Tisk
    // ali ponatis etikete statusa nikoli ne spremeni.
    const startStatus = RugStatus.awaitingPickup;

    final order = WorkOrder(
      id: id,
      location: location,
      channel: channel,
      handover: handover,
      status: OrderStatus.scheduledPickup,
      customerId: customer.id,
      customerName: customer.name,
      customerPhone: customer.phone,
      customerAddress: customer.fullAddress,
      itemCount: itemCount,
      pickupAt: pickupAt,
      pickupWindowEnd: pickupWindowEnd,
      deliveryAt: deliveryAt,
      dueAt: dueAt,
      deliveryFee: deliveryFee,
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
      nextOrderSeqLjubljana:
          location == OrderLocation.ljubljana ? seq + 1 : null,
      nextOrderSeqMaribor: location == OrderLocation.maribor ? seq + 1 : null,
      nextOrderSeqCelje: location == OrderLocation.celje ? seq + 1 : null,
      nextOrderSeqDolenjska:
          location == OrderLocation.dolenjska ? seq + 1 : null,
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

  /// Izbriše odprto naročilo skupaj z vsemi njegovimi kosi (napačen vnos,
  /// podvojeno naročilo). Vrne false, če naročila ni ali je že zaključeno.
  ///
  /// Zaključeno naročilo se ne briše: hrani dokazilo o vračilu (podpis), zaradi
  /// katerega aplikacija sploh obstaja. Števec številk se ne zmanjša — natisnjena
  /// etiketa izbrisanega naročila je lahko še na preprogi, zato se številka ne
  /// sme ponovno uporabiti za drugo stranko.
  bool deleteOrder(String orderId) {
    final order = state.order(orderId);
    if (order == null || !order.status.isOpen) return false;
    _commit(state.copyWith(
      orders: state.orders.where((o) => o.id != orderId).toList(),
      items: state.items.where((i) => i.orderId != orderId).toList(),
    ));
    return true;
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
    // Če naročilo še ni prišlo v proces, tudi nov kos počaka z ostalimi.
    final startStatus = existing.every((i) => i.status == RugStatus.awaitingPickup)
        ? RugStatus.awaitingPickup
        : RugStatus.awaitingWash;
    final fresh = RugItem(
      id: '$orderId-$total',
      orderId: orderId,
      index: total,
      ofTotal: total,
      status: startStatus,
      history: [
        StatusEvent(
          status: startStatus,
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

  /// Odstrani kos iz naročila (npr. napačno štetje ob sprejemu).
  ///
  /// ID-ji preostalih kosov ostanejo nespremenjeni — že natisnjena QR
  /// etiketa se ne sme premakniti na drug kos — spremeni se le `ofTotal`,
  /// da nalepke in napredek spet kažejo pravilno skupno število.
  void removeItemFromOrder(String itemId) {
    final item = state.item(itemId);
    if (item == null) return;
    final order = state.order(item.orderId);
    if (order == null) return;

    final remaining =
        state.itemsOf(item.orderId).where((i) => i.id != itemId).toList();
    if (remaining.isEmpty) {
      throw StateError('Naročilo mora imeti vsaj en kos.');
    }
    final total = remaining.length;
    final renumbered =
        remaining.map((i) => i.copyWith(ofTotal: total)).toList();

    final items = [
      ...state.items.where((i) => i.orderId != item.orderId),
      ...renumbered,
    ];
    final orders = [...state.orders];
    final oi = orders.indexWhere((o) => o.id == item.orderId);
    orders[oi] = order.copyWith(itemCount: total);

    _commit(_recompute(
      state.copyWith(items: items, orders: orders),
      item.orderId,
    ));
  }

  /// Preproge smo pobrali pri stranki — vse čakajo na pranje.
  void markOrderPickedUp(String orderId, {String note = 'Prevzeto pri stranki'}) {
    final now = DateTime.now();
    final items = state.items.map((i) {
      if (i.orderId != orderId || i.status != RugStatus.awaitingPickup) return i;
      return i.copyWith(
        status: RugStatus.awaitingWash,
        history: [..._event(i, RugStatus.awaitingWash, now, note)],
      );
    }).toList();
    _commit(_recompute(state.copyWith(items: items), orderId));
  }

  /// Potrditev fizičnega prevzema (V8 §2): doplačila, ki jih delavec dejansko
  /// vidi, se zapišejo na naročilo (Vnos/Iznos) in na kose (Urin/Dlake), šele
  /// nato kosi preidejo v Čaka pranje. Hitri obračun jih pozneje samo pokaže
  /// že označena in izračuna Urin po izmerjenih m².
  void confirmPickup(
    String orderId, {
    List<AppliedExtra> orderExtras = const [],
    Map<String, List<AppliedExtra>> itemExtras = const {},
    String note = 'Prevzeto pri stranki',
  }) {
    final order = state.order(orderId);
    if (order == null) return;
    final now = DateTime.now();

    final items = state.items.map((i) {
      if (i.orderId != orderId || i.status != RugStatus.awaitingPickup) return i;
      return i.copyWith(
        status: RugStatus.awaitingWash,
        extras: itemExtras[i.id] ?? i.extras,
        history: [..._event(i, RugStatus.awaitingWash, now, note)],
      );
    }).toList();
    final orders = state.orders
        .map((o) => o.id == orderId ? o.copyWith(orderExtras: orderExtras) : o)
        .toList();
    _commit(_recompute(state.copyWith(items: items, orders: orders), orderId));
  }

  /// Stranko smo poklicali (osebni prevzem): prvi klic se zabeleži, ponovni
  /// ne prepiše časa — vrstica kaže "Klicano 6. 10. 14:30".
  void markCalled(String orderId) {
    final order = state.order(orderId);
    if (order == null || order.calledAt != null) return;
    updateOrder(order.copyWith(calledAt: DateTime.now()));
  }

  /// Naročilo za dostavo gre v kombi → prestavi se v zavihek Dostave.
  void sendToVan(String orderId) {
    final order = state.order(orderId);
    if (order == null || order.status != OrderStatus.awaitingDelivery) return;
    if (order.inVanAt != null) return;
    updateOrder(order.copyWith(inVanAt: DateTime.now()));
  }

  /// Undo: naročilo ni šlo v kombi — nazaj v Pripravljeno.
  void removeFromVan(String orderId) {
    final order = state.order(orderId);
    if (order == null || order.inVanAt == null) return;
    updateOrder(order.copyWith(clearInVanAt: true));
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
        // Prevzem ni samodejen korak: zahteva potrditev z doplačili
        // (`confirmPickup`), skeniranje ali tisk ga ne smeta preskočiti.
        RugStatus.awaitingPickup => null,
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

  /// Undo zadnjega samodejnega premika (po skeniranju): kos se vrne v
  /// prejšnji status, zadnji dogodek zgodovine pa se izbriše, da v zgodovini
  /// ne ostane šum. Vrne false, če kosa ni mogoče vrniti.
  bool undoAdvance(String itemId) {
    final item = state.item(itemId);
    if (item == null || item.history.length < 2) return false;
    final history = item.history.sublist(0, item.history.length - 1);
    _saveItem(item.copyWith(status: history.last.status, history: history));
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

  /// Hitri obračun (v3 spec §3/§4): mere, vrsta, doplačila in cena v enem
  /// koraku, naravnost iz Sušenja v Pripravljeno — brez postanka na
  /// "Mere in cena", da se ta status ne pokaže kot ločena čakalna vrsta.
  /// [setMeasurements] in [finishItem] ostajata za urejanje že izmerjenih
  /// kosov (npr. ročni popravek statusa nazaj na "Mere in cena").
  void finishRugFromDrying(
    String itemId, {
    double? widthCm,
    double? lengthCm,
    double? manualM2,
    required RugType rugType,
    required List<AppliedExtra> extras,
    required double discountPercent,
    double? priceOverride,
    String notes = '',
  }) {
    final item = state.item(itemId);
    if (item == null) return;
    final measured = item.copyWith(
      widthCm: widthCm,
      lengthCm: lengthCm,
      manualM2: manualM2,
      clearManualM2: manualM2 == null,
      rugTypeId: rugType.id,
      rugTypeName: rugType.name,
      pricePerM2: rugType.pricePerM2,
      minChargeM2: rugType.minChargeM2,
      extras: extras,
      discountPercent: discountPercent,
      notes: notes,
    );
    final finalPrice = priceOverride ?? measured.computedPrice;
    _saveItem(measured.copyWith(
      status: RugStatus.ready,
      confirmedPrice: finalPrice,
      history: _event(
        item,
        RugStatus.ready,
        DateTime.now(),
        'Hitri obračun potrjen: ${finalPrice.toStringAsFixed(2)} €',
      ),
    ));
  }

  /// Popravek že obračunanega kosa: vrsta, mere, doplačila, popust in končna
  /// cena. Status se ne spremeni (kos ne gre nazaj v Sušenje), površina, osnova
  /// in obračun naročila se izpeljejo iz kosa, zato se osvežijo sami.
  ///
  /// [extras] in [discountPercent] ostaneta, kot sta bila, če nista podana.
  /// V zgodovino se zapiše samo, kar se je res spremenilo; popravek brez
  /// sprememb ne naredi ničesar. Vrnjenega kosa ni mogoče popraviti.
  void editItemPricing(
    String itemId, {
    double? widthCm,
    double? lengthCm,
    double? manualM2,
    required RugType rugType,
    List<AppliedExtra>? extras,
    double? discountPercent,
    required double price,
  }) {
    final item = state.item(itemId);
    if (item == null || item.status == RugStatus.returned) return;
    final updated = item.copyWith(
      widthCm: widthCm,
      lengthCm: lengthCm,
      manualM2: manualM2,
      clearManualM2: manualM2 == null,
      rugTypeId: rugType.id,
      rugTypeName: rugType.name,
      pricePerM2: rugType.pricePerM2,
      minChargeM2: rugType.minChargeM2,
      extras: extras,
      discountPercent: discountPercent,
      confirmedPrice: price,
    );

    String extrasKey(List<AppliedExtra> list) =>
        (list.map((e) => '${e.name}|${e.kind.name}|${e.value}').toList()
              ..sort())
            .join(';');

    final changes = [
      if (updated.rugTypeId != item.rugTypeId ||
          updated.pricePerM2 != item.pricePerM2 ||
          updated.minChargeM2 != item.minChargeM2)
        'vrsta',
      if (updated.widthCm != item.widthCm ||
          updated.lengthCm != item.lengthCm ||
          updated.manualM2 != item.manualM2)
        'mere',
      if (extrasKey(updated.extras) != extrasKey(item.extras)) 'doplačila',
      if (updated.discountPercent != item.discountPercent) 'popust',
      if ((price - item.price).abs() > 0.004) 'cena',
    ];
    if (changes.isEmpty) return;

    _saveItem(updated.copyWith(
      history: _event(
        item,
        item.status,
        DateTime.now(),
        'Popravljeno (${changes.join(', ')}): ${price.toStringAsFixed(2)} €',
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

  /// Kosi ob izmeri prevzamejo ime in ceno vrste v svoja polja, zato brisanje
  /// šifranta ne spremeni že obračunanih kosov.
  void deleteRugType(String id) {
    _commit(state.copyWith(
      rugTypes: state.rugTypes.where((t) => t.id != id).toList(),
    ));
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

  ExtraTemplate createExtraTemplate(
    String name,
    ExtraKind kind,
    double value, {
    List<double> choices = const [],
  }) {
    final t = ExtraTemplate(
      id: _uuid.v4(),
      name: name,
      kind: kind,
      value: value,
      choices: choices,
    );
    upsertExtraTemplate(t);
    return t;
  }

  /// Kosi ob obračunu prevzamejo doplačilo v svoja polja, zato brisanje
  /// šifranta ne spremeni že obračunanih kosov.
  void deleteExtraTemplate(String id) {
    _commit(state.copyWith(
      extraTemplates: state.extraTemplates.where((t) => t.id != id).toList(),
    ));
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

    // Kombi in klic veljata samo, dokler je naročilo pripravljeno za predajo:
    // če se kos vrne v pranje, mora naročilo ob naslednji pripravljenosti spet
    // skozi V kombi / Pokliči.
    final keepVan = next == OrderStatus.awaitingDelivery;
    final keepCall = next.isHandoverReady || next == OrderStatus.completed;

    if (next == order.status &&
        readyAt == order.readyAt &&
        (keepVan || order.inVanAt == null) &&
        (keepCall || order.calledAt == null)) {
      return s;
    }
    orders[oi] = order.copyWith(
      status: next,
      readyAt: readyAt,
      clearReadyAt: readyAt == null,
      clearInVanAt: !keepVan && next != OrderStatus.completed,
      clearCalledAt: !keepCall,
    );
    return s.copyWith(orders: orders);
  }
}
