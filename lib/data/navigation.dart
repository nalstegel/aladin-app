import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Izbrani zavihek v spodnji vrstici.
final shellTabProvider = StateProvider<int>((ref) => 0);

const shellTabDashboard = 0;
const shellTabOrders = 1;
const shellTabScanner = 2;
const shellTabCustomers = 3;
const shellTabMore = 4;
