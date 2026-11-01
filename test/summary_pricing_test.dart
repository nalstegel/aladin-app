import 'dart:convert';
import 'dart:io';

import 'package:aladin/data/billing.dart';
import 'package:aladin/models/order.dart';
import 'package:aladin/models/rug_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// `functions/summaries.js` has its own copy of `billingFor()` (Cloud Functions
/// can't import Dart). Both sides run the same cases from one shared file, so a
/// change to the pricing here that isn't mirrored there fails a test instead of
/// quietly sending the owner a wrong revenue figure.
///
/// The JS half is `functions/test/summaries.test.js`.
void main() {
  final cases = (jsonDecode(
    File('functions/test/fixtures/pricing_cases.json').readAsStringSync(),
  ) as List)
      .cast<Map<String, dynamic>>();

  test('fixture is not empty', () => expect(cases, isNotEmpty));

  for (final c in cases) {
    test(c['name'] as String, () {
      final order = WorkOrder.fromJson(c['order'] as Map<String, dynamic>);
      final items = (c['items'] as List)
          .map((i) => RugItem.fromJson(i as Map<String, dynamic>))
          .toList();

      expect(
        double.parse(billingFor(order, items).total.toStringAsFixed(2)),
        (c['total'] as num).toDouble(),
      );
    });
  }
}
