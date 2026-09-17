// Vsi statusi in tipi v sistemu Aladin.

/// Kako je naročilo prišlo v sistem — ustreza trem zavihkom na vrhu.
enum OrderChannel { delivery, dropoff, b2b }

extension OrderChannelX on OrderChannel {
  String get label => switch (this) {
        OrderChannel.delivery => 'Dostava',
        OrderChannel.dropoff => 'Pripeljano',
        OrderChannel.b2b => 'B2B',
      };
  String get short => switch (this) {
        OrderChannel.delivery => 'DOST',
        OrderChannel.dropoff => 'PRIP',
        OrderChannel.b2b => 'B2B',
      };
}

/// Poslovalnica, kjer je bilo naročilo sprejeto — določi predpono
/// zaporedne številke naročila (glej `lib/core/order_id.dart`).
enum OrderLocation { ljubljana, maribor }

extension OrderLocationX on OrderLocation {
  String get label => switch (this) {
        OrderLocation.ljubljana => 'Ljubljana',
        OrderLocation.maribor => 'Maribor',
      };
  String get code => switch (this) {
        OrderLocation.ljubljana => 'LJ',
        OrderLocation.maribor => 'MB',
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
        RugStatus.awaitingPickup => 'V prevzemu',
        RugStatus.awaitingWash => 'Na pranju',
        RugStatus.drying => 'V sušenju',
        RugStatus.finishing => 'Mere in cena',
        // Namenoma "Vrnjeno", ne "Vračano" iz predloge: status pomeni, da je
        // preproga že vrnjena, "Vračano" pa bi se bralo kot postopek v teku.
        RugStatus.ready => 'Pripravljeno',
        RugStatus.returned => 'Vrnjeno',
      };

  /// Besedilo gumba, ki premakne preprogo v naslednji korak.
  String? get nextActionLabel => switch (this) {
        RugStatus.awaitingPickup => 'Prevzeto pri stranki',
        RugStatus.awaitingWash => 'Oprano → v sušenje',
        RugStatus.drying => 'Suho → vnesi mere',
        RugStatus.finishing => 'Vnesi mere in ceno',
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

  /// Kako se reče kosu, ki je ta korak *že opravil* — za napredek na kartici
  /// naročila ("3/8 oprano"). Ni isto kot `label`, ki opisuje trenutno stanje.
  String get doneLabel => switch (this) {
        RugStatus.awaitingPickup => 'prevzeto',
        RugStatus.awaitingWash => 'oprano',
        RugStatus.drying => 'posušeno',
        RugStatus.finishing => 'izmerjeno',
        RugStatus.ready => 'pripravljeno',
        RugStatus.returned => 'vrnjeno',
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
