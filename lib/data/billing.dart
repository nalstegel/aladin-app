import '../models/enums.dart';
import '../models/order.dart';
import '../models/rug_item.dart';

/// Najmanjši znesek naročila pri našem prevzemu / dostavi (V8 §3).
const minimumDeliveryOrderTotal = 50.0;

/// Končni obračun naročila: kosi + doplačila prevzema + dostava + minimum.
///
/// Cena kosa ostane njegova (ročno popravljiva); minimum 50 € je vrstica na
/// ravni naročila, da razlika ni skrita v enem kosu.
class OrderBilling {
  const OrderBilling({
    required this.itemsTotal,
    required this.orderExtrasTotal,
    required this.deliveryFee,
    required this.minimumTopUp,
    required this.allPriced,
  });

  final double itemsTotal;
  final double orderExtrasTotal;
  final double deliveryFee;

  /// Doplačilo do minimuma 50 €. 0, dokler niso vsi kosi obračunani — prej
  /// bi minimum prikazal napačno razliko.
  final double minimumTopUp;

  /// Ali so vsi kosi že obračunani (Pripravljeno / Vrnjeno).
  final bool allPriced;

  double get subtotal => itemsTotal + orderExtrasTotal + deliveryFee;
  double get total => subtotal + minimumTopUp;
}

/// [priceOverrides] omogoča predogled: cena kosa, ki se ravnokar obračunava
/// (ID kosa → cena), še preden je shranjena.
OrderBilling billingFor(
  WorkOrder order,
  List<RugItem> items, {
  Map<String, double> priceOverrides = const {},
}) {
  var itemsTotal = 0.0;
  var allPriced = items.isNotEmpty;
  for (final i in items) {
    final override = priceOverrides[i.id];
    if (override != null) {
      itemsTotal += override;
    } else if (i.status == RugStatus.ready || i.status == RugStatus.returned) {
      itemsTotal += i.price;
    } else {
      // Kos še ni obračunan: šteje, kar je že znano (stari podatki imajo
      // lahko ceno že pred potrditvijo), vendar minimuma še ne uveljavimo.
      itemsTotal += i.price;
      allPriced = false;
    }
  }

  final extras = order.orderExtras.fold<double>(
    0,
    (s, e) => s + e.amount(base: 0, m2: 0),
  );
  final fee = order.deliveryFee;
  final subtotal = itemsTotal + extras + fee;

  final appliesMinimum = order.channel == OrderChannel.delivery;
  final topUp = appliesMinimum &&
          allPriced &&
          subtotal < minimumDeliveryOrderTotal
      ? double.parse((minimumDeliveryOrderTotal - subtotal).toStringAsFixed(2))
      : 0.0;

  return OrderBilling(
    itemsTotal: itemsTotal,
    orderExtrasTotal: extras,
    deliveryFee: fee,
    minimumTopUp: topUp,
    allPriced: allPriced,
  );
}
