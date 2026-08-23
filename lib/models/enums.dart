// Vsi statusi in tipi v sistemu Aladin.

/// Kako je naročilo prišlo v sistem — ustreza trem zavihkom na vrhu.
enum OrderChannel { delivery, dropoff, b2b }

extension OrderChannelX on OrderChannel {
  String get label => switch (this) {
        OrderChannel.delivery => 'Dostava',
        OrderChannel.dropoff => 'Osebni prevzem',
        OrderChannel.b2b => 'B2B',
      };
  String get short => switch (this) {
        OrderChannel.delivery => 'DOST',
        OrderChannel.dropoff => 'OSEB',
        OrderChannel.b2b => 'B2B',
      };
}

/// Kako preproge pridejo nazaj do stranke.
enum HandoverMode { customerCollects, weDeliver }

extension HandoverModeX on HandoverMode {
  String get label => switch (this) {
        HandoverMode.customerCollects => 'Stranka pride po preproge',
        HandoverMode.weDeliver => 'Mi dostavimo',
      };
}

/// Status celotnega naročila. Aplikacija ga vedno izračuna iz stanja kosov.
enum OrderStatus {
  scheduledPickup,
  inProduction,
  awaitingCollection,
  awaitingDelivery,
  completed,
  cancelled,
}

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.scheduledPickup => 'Za prevzem',
        OrderStatus.inProduction => 'V obdelavi',
        OrderStatus.awaitingCollection => 'Čaka na prevzem',
        OrderStatus.awaitingDelivery => 'Čaka na vračilo',
        OrderStatus.completed => 'Zaključeno',
        OrderStatus.cancelled => 'Preklicano',
      };
  bool get isOpen =>
      this != OrderStatus.completed && this != OrderStatus.cancelled;
  bool get isHandoverReady =>
      this == OrderStatus.awaitingCollection ||
      this == OrderStatus.awaitingDelivery;
}

/// Status posamezne preproge — glavna logika proizvodnje.
enum RugStatus {
  awaitingPickup,
  awaitingWash,
  drying,
  finishing,
  ready,
  returned,
}

extension RugStatusX on RugStatus {
  String get label => switch (this) {
        RugStatus.awaitingPickup => 'Za prevzem',
        RugStatus.awaitingWash => 'Čaka na pranje',
        RugStatus.drying => 'Sušenje',
        RugStatus.finishing => 'Končna obdelava',
        RugStatus.ready => 'READY',
        RugStatus.returned => 'Vrnjeno',
      };

  /// Besedilo gumba, ki premakne preprogo v naslednji korak.
  String? get nextActionLabel => switch (this) {
        RugStatus.awaitingPickup => 'Prevzeto pri stranki',
        RugStatus.awaitingWash => 'Oprano → sušenje',
        RugStatus.drying => 'Suho → vnesi mere',
        RugStatus.finishing => 'Končna obdelava in cena',
        RugStatus.ready => null,
        RugStatus.returned => null,
      };

  int get order => switch (this) {
        RugStatus.awaitingPickup => 0,
        RugStatus.awaitingWash => 1,
        RugStatus.drying => 2,
        RugStatus.finishing => 3,
        RugStatus.ready => 4,
        RugStatus.returned => 5,
      };
}

/// Način obračuna doplačila ali popusta.
enum ExtraKind { perM2, fixed, percent }

extension ExtraKindX on ExtraKind {
  String get label => switch (this) {
        ExtraKind.perM2 => '€/m²',
        ExtraKind.fixed => '€',
        ExtraKind.percent => '%',
      };
}

enum CustomerType { private, company }

extension CustomerTypeX on CustomerType {
  String get label => switch (this) {
        CustomerType.private => 'Fizična oseba',
        CustomerType.company => 'Podjetje / B2B',
      };
}

enum UserRole { worker, admin }

extension UserRoleX on UserRole {
  String get label =>
      this == UserRole.admin ? 'Administrator' : 'Zaposleni';
}
