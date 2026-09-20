import '../models/app_user.dart';
import '../models/catalog.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../models/return_proof.dart';
import '../models/rug_item.dart';
import '../models/status_event.dart';
import 'app_state.dart';

/// Začetni demo podatki, da je aplikacija ob prvem zagonu uporabna.
AppState buildSeedState() {
  final now = DateTime.now();
  DateTime day(int offset, [int hour = 9, int minute = 0]) => DateTime(
        now.year,
        now.month,
        now.day + offset,
        hour,
        minute,
      );

  const users = [
    AppUser(id: 'u-nal', name: 'Nal', role: UserRole.admin),
    AppUser(id: 'u-marko', name: 'Marko', role: UserRole.worker),
    AppUser(id: 'u-ana', name: 'Ana', role: UserRole.worker),
  ];

  // Štiri vrste in štiri doplačila, poimenovani in prešteti natanko po v3
  // spec §4 (kompaktna mreža v hitrem obračunu). Id-ji ostajajo stari, da
  // zgodovinski kosi spodaj (rugTypeName/AppliedExtra so lastni posnetki,
  // neodvisni od šifranta) niso prizadeti — glej models/catalog.dart.
  const rugTypes = [
    RugType(id: 't-sint', name: 'Navadna', pricePerM2: 12, minChargeM2: 3),
    RugType(id: 't-volna', name: 'Volna', pricePerM2: 15, minChargeM2: 3),
    RugType(id: 't-perzija', name: 'Perzijska', pricePerM2: 22, minChargeM2: 2),
    RugType(id: 't-shaggy', name: 'Shaggy', pricePerM2: 16, minChargeM2: 3),
  ];

  const extras = [
    ExtraTemplate(id: 'e-dlake', name: 'Dlake', kind: ExtraKind.percent, value: 15),
    ExtraTemplate(id: 'e-vonj', name: 'Urin / vonj', kind: ExtraKind.fixed, value: 8),
    ExtraTemplate(id: 'e-madezi', name: 'Dodatna umazanija', kind: ExtraKind.percent, value: 20),
    ExtraTemplate(id: 'e-drugo', name: 'Drugo / popravek', kind: ExtraKind.fixed, value: 10),
  ];

  final customers = [
    Customer(
      id: 'c-novak',
      type: CustomerType.private,
      name: 'Janez Novak',
      phone: '041 234 567',
      email: 'janez.novak@email.si',
      address: 'Trubarjeva 12',
      city: 'Ljubljana',
      postalCode: '1000',
      createdAt: now.subtract(const Duration(days: 420)),
    ),
    Customer(
      id: 'c-kovac',
      type: CustomerType.private,
      name: 'Marija Kovač',
      phone: '031 887 220',
      address: 'Cesta na Brdo 44',
      city: 'Ljubljana',
      postalCode: '1000',
      notes: 'Zvonec ne dela, pokliči ob prihodu.',
      createdAt: now.subtract(const Duration(days: 210)),
    ),
    Customer(
      id: 'c-horvat',
      type: CustomerType.private,
      name: 'Peter Horvat',
      phone: '051 402 118',
      address: 'Kajuhova 8',
      city: 'Domžale',
      postalCode: '1230',
      createdAt: now.subtract(const Duration(days: 95)),
    ),
    Customer(
      id: 'c-slon',
      type: CustomerType.company,
      name: 'Hotel Slon d.d.',
      phone: '01 470 11 00',
      email: 'housekeeping@hotelslon.com',
      address: 'Slovenska cesta 34',
      city: 'Ljubljana',
      postalCode: '1000',
      taxId: 'SI12345678',
      contactPerson: 'Tanja Zupan, vodja gospodinjstva',
      defaultDiscountPercent: 10,
      createdAt: now.subtract(const Duration(days: 640)),
    ),
    Customer(
      id: 'c-soncek',
      type: CustomerType.company,
      name: 'Vrtec Sonček',
      phone: '01 512 33 44',
      email: 'tajnistvo@vrtec-soncek.si',
      address: 'Ulica bratov Učakar 5',
      city: 'Ljubljana',
      postalCode: '1000',
      taxId: 'SI87654321',
      contactPerson: 'Mateja Rus',
      defaultDiscountPercent: 5,
      notes: 'Račun na občino, dostava samo dopoldne.',
      createdAt: now.subtract(const Duration(days: 300)),
    ),
  ];

  final orders = <WorkOrder>[];
  final items = <RugItem>[];

  StatusEvent ev(RugStatus s, DateTime at, String who, [String note = '']) =>
      StatusEvent(
        status: s,
        at: at,
        userId: 'u-marko',
        userName: who,
        note: note,
      );

  // -------------------------------------------------- LJ-005 primer iz koncepta
  // Novak ima 3 kose: dva sta pripravljena, tretji je še v sušilnici.
  orders.add(WorkOrder(
    id: 'LJ-005',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.dropoff,
    handover: HandoverMode.customerCollects,
    status: OrderStatus.inProduction,
    customerId: 'c-novak',
    customerName: 'Janez Novak',
    customerPhone: '041 234 567',
    customerAddress: 'Trubarjeva 12, 1000 Ljubljana',
    itemCount: 3,
    dueAt: day(2, 16),
    notes: 'Na največji preprogi madež od vina pri robu.',
    createdAt: day(-3, 10, 15),
    createdByName: 'Nal',
  ));
  items.addAll([
    RugItem(
      id: 'LJ-005-1',
      orderId: 'LJ-005',
      index: 1,
      ofTotal: 3,
      status: RugStatus.ready,
      widthCm: 200,
      lengthCm: 300,
      rugTypeId: 't-volna',
      rugTypeName: 'Volna',
      pricePerM2: 15,
      minChargeM2: 3,
      confirmedPrice: 108,
      extras: const [
        AppliedExtra(name: 'Odstranjevanje madežev', kind: ExtraKind.percent, value: 20),
      ],
      condition: 'Madež od vina pri robu.',
      history: [
        ev(RugStatus.awaitingWash, day(-3, 10, 15), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.drying, day(-2, 8, 40), 'Marko'),
        ev(RugStatus.finishing, day(-1, 9, 10), 'Ana', 'Mere in vrsta vnesene'),
        ev(RugStatus.ready, day(-1, 11, 30), 'Ana', 'Cena potrjena: 108,00 €'),
      ],
    ),
    RugItem(
      id: 'LJ-005-2',
      orderId: 'LJ-005',
      index: 2,
      ofTotal: 3,
      status: RugStatus.ready,
      widthCm: 160,
      lengthCm: 230,
      rugTypeId: 't-sint',
      rugTypeName: 'Sintetika',
      pricePerM2: 12,
      minChargeM2: 3,
      confirmedPrice: 44.16,
      history: [
        ev(RugStatus.awaitingWash, day(-3, 10, 15), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.drying, day(-2, 8, 45), 'Marko'),
        ev(RugStatus.finishing, day(-1, 9, 20), 'Ana', 'Mere in vrsta vnesene'),
        ev(RugStatus.ready, day(-1, 11, 35), 'Ana', 'Cena potrjena: 44,16 €'),
      ],
    ),
    RugItem(
      id: 'LJ-005-3',
      orderId: 'LJ-005',
      index: 3,
      ofTotal: 3,
      status: RugStatus.drying,
      history: [
        ev(RugStatus.awaitingWash, day(-3, 10, 15), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.drying, day(0, 7, 55), 'Marko'),
      ],
    ),
  ]);

  // ------------------------------------------- LJ-002 vse gotovo, čaka stranko
  orders.add(WorkOrder(
    id: 'LJ-002',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.dropoff,
    handover: HandoverMode.customerCollects,
    status: OrderStatus.awaitingCollection,
    customerId: 'c-horvat',
    customerName: 'Peter Horvat',
    customerPhone: '051 402 118',
    customerAddress: 'Kajuhova 8, 1230 Domžale',
    itemCount: 2,
    dueAt: day(-1, 16),
    createdAt: day(-6, 14, 5),
    createdByName: 'Ana',
    readyAt: day(-1, 15, 20),
  ));
  items.addAll([
    RugItem(
      id: 'LJ-002-1',
      orderId: 'LJ-002',
      index: 1,
      ofTotal: 2,
      status: RugStatus.ready,
      widthCm: 140,
      lengthCm: 200,
      rugTypeId: 't-shaggy',
      rugTypeName: 'Shaggy / visoki flor',
      pricePerM2: 16,
      minChargeM2: 3,
      confirmedPrice: 44.80,
      history: [
        ev(RugStatus.awaitingWash, day(-6, 14, 5), 'Ana', 'Naročilo ustvarjeno'),
        ev(RugStatus.drying, day(-4, 9, 0), 'Marko'),
        ev(RugStatus.finishing, day(-2, 10, 0), 'Marko'),
        ev(RugStatus.ready, day(-1, 15, 20), 'Ana', 'Cena potrjena: 44,80 €'),
      ],
    ),
    RugItem(
      id: 'LJ-002-2',
      orderId: 'LJ-002',
      index: 2,
      ofTotal: 2,
      status: RugStatus.ready,
      widthCm: 80,
      lengthCm: 150,
      rugTypeId: 't-tekac',
      rugTypeName: 'Tekač / predpražnik',
      pricePerM2: 10,
      minChargeM2: 2,
      confirmedPrice: 20,
      history: [
        ev(RugStatus.awaitingWash, day(-6, 14, 5), 'Ana', 'Naročilo ustvarjeno'),
        ev(RugStatus.drying, day(-4, 9, 5), 'Marko'),
        ev(RugStatus.finishing, day(-2, 10, 5), 'Marko'),
        ev(RugStatus.ready, day(-1, 15, 22), 'Ana', 'Cena potrjena: 20,00 €'),
      ],
    ),
  ]);

  // ------------------------------------------------ LJ-003 dostava, za vračilo
  orders.add(WorkOrder(
    id: 'LJ-003',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.delivery,
    handover: HandoverMode.weDeliver,
    status: OrderStatus.awaitingDelivery,
    customerId: 'c-kovac',
    customerName: 'Marija Kovač',
    customerPhone: '031 887 220',
    customerAddress: 'Cesta na Brdo 44, 1000 Ljubljana',
    itemCount: 2,
    pickupAt: day(-5, 8, 30),
    deliveryAt: day(0, 15, 0),
    dueAt: day(0, 17),
    notes: 'Zvonec ne dela, pokliči ob prihodu.',
    createdAt: day(-6, 11, 0),
    createdByName: 'Nal',
    readyAt: day(-1, 16, 45),
  ));
  items.addAll([
    RugItem(
      id: 'LJ-003-1',
      orderId: 'LJ-003',
      index: 1,
      ofTotal: 2,
      status: RugStatus.ready,
      widthCm: 250,
      lengthCm: 350,
      rugTypeId: 't-perzija',
      rugTypeName: 'Perzija / ročno vozlana',
      pricePerM2: 22,
      minChargeM2: 2,
      confirmedPrice: 231,
      extras: const [
        AppliedExtra(name: 'Impregnacija', kind: ExtraKind.perM2, value: 2),
      ],
      condition: 'Rob rahlo obrabljen, resice na eni strani stanjšane.',
      history: [
        ev(RugStatus.awaitingPickup, day(-6, 11, 0), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.awaitingWash, day(-5, 8, 30), 'Marko', 'Prevzeto pri stranki'),
        ev(RugStatus.drying, day(-3, 9, 15), 'Marko'),
        ev(RugStatus.finishing, day(-2, 8, 30), 'Ana'),
        ev(RugStatus.ready, day(-1, 16, 45), 'Ana', 'Cena potrjena: 231,00 €'),
      ],
    ),
    RugItem(
      id: 'LJ-003-2',
      orderId: 'LJ-003',
      index: 2,
      ofTotal: 2,
      status: RugStatus.ready,
      widthCm: 120,
      lengthCm: 180,
      rugTypeId: 't-volna',
      rugTypeName: 'Volna',
      pricePerM2: 15,
      minChargeM2: 3,
      confirmedPrice: 32.40,
      history: [
        ev(RugStatus.awaitingPickup, day(-6, 11, 0), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.awaitingWash, day(-5, 8, 30), 'Marko', 'Prevzeto pri stranki'),
        ev(RugStatus.drying, day(-3, 9, 20), 'Marko'),
        ev(RugStatus.finishing, day(-2, 8, 35), 'Ana'),
        ev(RugStatus.ready, day(-1, 16, 46), 'Ana', 'Cena potrjena: 32,40 €'),
      ],
    ),
  ]);

  // ------------------------------------------------------ LJ-004 B2B v obdelavi
  orders.add(WorkOrder(
    id: 'LJ-004',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.b2b,
    handover: HandoverMode.weDeliver,
    status: OrderStatus.inProduction,
    customerId: 'c-slon',
    customerName: 'Hotel Slon d.d.',
    customerPhone: '01 470 11 00',
    customerAddress: 'Slovenska cesta 34, 1000 Ljubljana',
    itemCount: 4,
    pickupAt: day(-4, 7, 0),
    deliveryAt: day(1, 8, 0),
    dueAt: day(1, 12),
    notes: 'Preproge iz konferenčne dvorane, računi mesečno.',
    createdAt: day(-5, 9, 0),
    createdByName: 'Nal',
  ));
  for (var n = 1; n <= 4; n++) {
    final done = n <= 2;
    items.add(RugItem(
      id: 'LJ-004-$n',
      orderId: 'LJ-004',
      index: n,
      ofTotal: 4,
      status: done ? RugStatus.ready : (n == 3 ? RugStatus.drying : RugStatus.awaitingWash),
      widthCm: done ? 300 : null,
      lengthCm: done ? 400 : null,
      rugTypeId: done ? 't-sint' : null,
      rugTypeName: done ? 'Sintetika' : '',
      pricePerM2: done ? 12 : 0,
      minChargeM2: done ? 3 : 0,
      discountPercent: done ? 10 : 0,
      confirmedPrice: done ? 129.60 : null,
      history: [
        ev(RugStatus.awaitingPickup, day(-5, 9, 0), 'Nal', 'Naročilo ustvarjeno'),
        ev(RugStatus.awaitingWash, day(-4, 7, 0), 'Marko', 'Prevzeto pri stranki'),
        if (n <= 3) ev(RugStatus.drying, day(-2, 10, 0), 'Marko'),
        if (done) ev(RugStatus.finishing, day(-1, 9, 0), 'Ana'),
        if (done) ev(RugStatus.ready, day(-1, 13, 0), 'Ana', 'Cena potrjena: 129,60 €'),
      ],
    ));
  }

  // ------------------------------------------------- LJ-006 jutrišnji prevzem
  orders.add(WorkOrder(
    id: 'LJ-006',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.delivery,
    handover: HandoverMode.weDeliver,
    status: OrderStatus.scheduledPickup,
    customerId: 'c-soncek',
    customerName: 'Vrtec Sonček',
    customerPhone: '01 512 33 44',
    customerAddress: 'Ulica bratov Učakar 5, 1000 Ljubljana',
    itemCount: 5,
    pickupAt: day(1, 8, 0),
    dueAt: day(6, 12),
    notes: 'Igralnice 1–3, prevzem pri stranskem vhodu.',
    createdAt: day(0, 12, 30),
    createdByName: 'Nal',
  ));
  for (var n = 1; n <= 5; n++) {
    items.add(RugItem(
      id: 'LJ-006-$n',
      orderId: 'LJ-006',
      index: n,
      ofTotal: 5,
      status: RugStatus.awaitingPickup,
      history: [ev(RugStatus.awaitingPickup, day(0, 12, 30), 'Nal', 'Naročilo ustvarjeno')],
    ));
  }

  // ------------------------------------------ LJ-001 zaključeno, s podpisom
  orders.add(WorkOrder(
    id: 'LJ-001',
    location: OrderLocation.ljubljana,
    channel: OrderChannel.dropoff,
    handover: HandoverMode.customerCollects,
    status: OrderStatus.completed,
    customerId: 'c-novak',
    customerName: 'Janez Novak',
    customerPhone: '041 234 567',
    customerAddress: 'Trubarjeva 12, 1000 Ljubljana',
    itemCount: 1,
    createdAt: day(-40, 10, 0),
    createdByName: 'Ana',
    readyAt: day(-35, 12, 0),
    completedAt: day(-33, 17, 10),
    returnProof: ReturnProof(
      returnedAt: day(-33, 17, 10),
      userId: 'u-marko',
      userName: 'Marko',
      scannedItemIds: const ['LJ-001-1'],
      receivedByName: 'Janez Novak',
      signatureBase64: null,
      overrideReason: 'Demo podatek – podpis ni bil zajet.',
      overrideByName: 'Nal',
    ),
  ));
  items.add(RugItem(
    id: 'LJ-001-1',
    orderId: 'LJ-001',
    index: 1,
    ofTotal: 1,
    status: RugStatus.returned,
    widthCm: 200,
    lengthCm: 290,
    rugTypeId: 't-volna',
    rugTypeName: 'Volna',
    pricePerM2: 15,
    minChargeM2: 3,
    confirmedPrice: 87,
    history: [
      ev(RugStatus.awaitingWash, day(-40, 10, 0), 'Ana', 'Naročilo ustvarjeno'),
      ev(RugStatus.drying, day(-38, 9, 0), 'Marko'),
      ev(RugStatus.finishing, day(-36, 9, 0), 'Marko'),
      ev(RugStatus.ready, day(-35, 12, 0), 'Ana', 'Cena potrjena: 87,00 €'),
      ev(RugStatus.returned, day(-33, 17, 10), 'Marko', 'Vrnjeno'),
    ],
  ));

  return AppState(
    customers: customers,
    orders: orders,
    items: items,
    rugTypes: rugTypes,
    extraTemplates: extras,
    users: users,
    currentUserId: null,
    nextOrderSeqLjubljana: 7,
    nextOrderSeqMaribor: 1,
    nextOrderSeqCelje: 1,
  );
}
