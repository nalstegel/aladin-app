import '../models/app_user.dart';
import '../models/catalog.dart';
import '../models/customer.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../models/rug_item.dart';
import 'billing.dart';

/// Celotno stanje aplikacije. Nespremenljivo — vsaka sprememba ustvari novo.
class AppState {
  final List<Customer> customers;
  final List<WorkOrder> orders;
  final List<RugItem> items;
  final List<RugType> rugTypes;
  final List<ExtraTemplate> extraTemplates;
  final List<AppUser> users;
  final String? currentUserId;

  /// Naslednja zaporedna številka naročila za vsako območje posebej
  /// (glej `lib/core/order_id.dart` za format LJ-001/MB-001…). Šteje se od
  /// začetka in se nikoli ne ponastavi.
  final int nextOrderSeqLjubljana;
  final int nextOrderSeqMaribor;
  final int nextOrderSeqCelje;
  final int nextOrderSeqDolenjska;

  const AppState({
    this.customers = const [],
    this.orders = const [],
    this.items = const [],
    this.rugTypes = const [],
    this.extraTemplates = const [],
    this.users = const [],
    this.currentUserId,
    this.nextOrderSeqLjubljana = 1,
    this.nextOrderSeqMaribor = 1,
    this.nextOrderSeqCelje = 1,
    this.nextOrderSeqDolenjska = 1,
  });

  int nextOrderSeq(OrderLocation location) => switch (location) {
        OrderLocation.ljubljana => nextOrderSeqLjubljana,
        OrderLocation.maribor => nextOrderSeqMaribor,
        OrderLocation.celje => nextOrderSeqCelje,
        OrderLocation.dolenjska => nextOrderSeqDolenjska,
      };

  AppUser? get currentUser {
    if (currentUserId == null) return null;
    for (final u in users) {
      if (u.id == currentUserId) return u;
    }
    return null;
  }

  AppUser? user(String id) {
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

  Customer? customer(String id) {
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  WorkOrder? order(String id) {
    for (final o in orders) {
      if (o.id == id) return o;
    }
    return null;
  }

  RugItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  RugType? rugType(String id) {
    for (final t in rugTypes) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Kosi naročila, urejeni po zaporedni številki.
  List<RugItem> itemsOf(String orderId) {
    final list = items.where((i) => i.orderId == orderId).toList();
    list.sort((a, b) => a.index.compareTo(b.index));
    return list;
  }

  List<WorkOrder> ordersOf(String customerId) {
    final list = orders.where((o) => o.customerId == customerId).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Koliko kosov naročila je že pripravljenih (ali vrnjenih).
  int readyCount(String orderId) => itemsOf(orderId)
      .where((i) => i.status == RugStatus.ready || i.status == RugStatus.returned)
      .length;

  /// Končni obračun naročila: kosi, doplačila ob prevzemu, dostava in
  /// minimum 50 € (glej `billing.dart`).
  OrderBilling? billing(String orderId) {
    final o = order(orderId);
    return o == null ? null : billingFor(o, itemsOf(orderId));
  }

  double orderTotal(String orderId) =>
      billing(orderId)?.total ??
      itemsOf(orderId).fold<double>(0, (s, i) => s + i.price);

  double orderM2(String orderId) =>
      itemsOf(orderId).fold<double>(0, (s, i) => s + i.m2);

  /// Vsi odprti kosi v danem statusu — za nadzorno ploščo.
  List<RugItem> itemsByStatus(RugStatus status) =>
      items.where((i) => i.status == status).toList();

  AppState copyWith({
    List<Customer>? customers,
    List<WorkOrder>? orders,
    List<RugItem>? items,
    List<RugType>? rugTypes,
    List<ExtraTemplate>? extraTemplates,
    List<AppUser>? users,
    String? currentUserId,
    int? nextOrderSeqLjubljana,
    int? nextOrderSeqMaribor,
    int? nextOrderSeqCelje,
    int? nextOrderSeqDolenjska,
    bool clearCurrentUser = false,
  }) =>
      AppState(
        customers: customers ?? this.customers,
        orders: orders ?? this.orders,
        items: items ?? this.items,
        rugTypes: rugTypes ?? this.rugTypes,
        extraTemplates: extraTemplates ?? this.extraTemplates,
        users: users ?? this.users,
        currentUserId:
            clearCurrentUser ? null : (currentUserId ?? this.currentUserId),
        nextOrderSeqLjubljana: nextOrderSeqLjubljana ?? this.nextOrderSeqLjubljana,
        nextOrderSeqMaribor: nextOrderSeqMaribor ?? this.nextOrderSeqMaribor,
        nextOrderSeqCelje: nextOrderSeqCelje ?? this.nextOrderSeqCelje,
        nextOrderSeqDolenjska:
            nextOrderSeqDolenjska ?? this.nextOrderSeqDolenjska,
      );

  Map<String, dynamic> toJson() => {
        'customers': customers.map((e) => e.toJson()).toList(),
        'orders': orders.map((e) => e.toJson()).toList(),
        'items': items.map((e) => e.toJson()).toList(),
        'rugTypes': rugTypes.map((e) => e.toJson()).toList(),
        'extraTemplates': extraTemplates.map((e) => e.toJson()).toList(),
        'users': users.map((e) => e.toJson()).toList(),
        'currentUserId': currentUserId,
        'nextOrderSeqLjubljana': nextOrderSeqLjubljana,
        'nextOrderSeqMaribor': nextOrderSeqMaribor,
        'nextOrderSeqCelje': nextOrderSeqCelje,
        'nextOrderSeqDolenjska': nextOrderSeqDolenjska,
      };

  factory AppState.fromJson(Map<String, dynamic> j) {
    List<T> parse<T>(String key, T Function(Map<String, dynamic>) f) =>
        (j[key] as List? ?? [])
            .map((e) => f(e as Map<String, dynamic>))
            .toList();
    return AppState(
      customers: parse('customers', Customer.fromJson),
      orders: parse('orders', WorkOrder.fromJson),
      items: parse('items', RugItem.fromJson),
      rugTypes: parse('rugTypes', RugType.fromJson),
      extraTemplates: parse('extraTemplates', ExtraTemplate.fromJson),
      users: parse('users', AppUser.fromJson),
      currentUserId: j['currentUserId'] as String?,
      nextOrderSeqLjubljana: j['nextOrderSeqLjubljana'] as int? ?? 1,
      nextOrderSeqMaribor: j['nextOrderSeqMaribor'] as int? ?? 1,
      nextOrderSeqCelje: j['nextOrderSeqCelje'] as int? ?? 1,
      nextOrderSeqDolenjska: j['nextOrderSeqDolenjska'] as int? ?? 1,
    );
  }
}
