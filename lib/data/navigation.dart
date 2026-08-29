import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Izbrani zavihek v spodnji vrstici. Kot provider zato, da lahko tudi
/// zasloni zunaj ogrodja (npr. "Zaključena naročila" v meniju Več) skočijo
/// na pravi zavihek, namesto da bi isti seznam podvajali.
final shellTabProvider = StateProvider<int>((ref) => 0);

/// Zavihek znotraj Naročil: 0 = Aktivna, 1 = Zaključena.
final ordersTabProvider = StateProvider<int>((ref) => 0);

const shellTabDashboard = 0;
const shellTabOrders = 1;
const shellTabScanner = 2;
const shellTabCustomers = 3;
const shellTabMore = 4;
