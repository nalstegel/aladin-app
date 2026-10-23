import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/launch.dart';
import '../../data/providers.dart';
import '../../models/order.dart';

/// Pokliči stranko naročila.
///
/// Vsak vstopni kanal za klic (seznam Pripravljeno, podrobnosti naročila,
/// telefonska ikona) mora iti skozi to funkcijo — tako se klic zabeleži
/// (`calledAt`) ne glede na to, od kod je sprožen (V10 §2). Že sprožen klic
/// šteje kot Klicano, tudi če klicalnik potem ne uspe, zato se zabeleži
/// preden se odpre.
Future<void> callCustomer(
  BuildContext context,
  WidgetRef ref,
  WorkOrder order,
) async {
  final messenger = ScaffoldMessenger.of(context);
  ref.read(repositoryProvider.notifier).markCalled(order.id);
  var ok = false;
  try {
    ok = await callPhone(order.customerPhone);
  } catch (_) {}
  if (!ok) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Klica ni bilo mogoče začeti.')),
    );
  }
}
