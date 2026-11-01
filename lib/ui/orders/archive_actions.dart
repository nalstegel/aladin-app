import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../data/repository.dart';
import '../../models/order.dart';
import '../widgets/undo_snackbar.dart';

/// "Premakni v arhiv" from the order detail: confirm, then back to the first
/// screen with an undo snackbar.
///
/// The order is not written until the detail screen has closed — otherwise it
/// would switch to the archived (button-less) layout during the closing
/// animation. Same pattern as deleting an order.
Future<void> confirmArchiveOrder(
  BuildContext context,
  Repository repo,
  WorkOrder order,
  int itemCount,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Premakni naročilo v arhiv?'),
      content: Text(
        '${order.number} · ${order.customerName} · ${Fmt.pieces(itemCount)}\n\n'
        'Naročilo izgine iz vseh aktivnih zavihkov in števcev. Podatki, kosi, '
        'cena in zgodovina ostanejo ohranjeni. Vrneš ga lahko v Več → Arhiv.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Prekliči'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Premakni'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final route = ModalRoute.of(context);

  navigator.popUntil((r) => r.isFirst);
  await route?.completed;

  if (!repo.archiveOrder(order.id)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Naročila ${order.number} ni bilo mogoče arhivirati.'),
      ),
    );
    return;
  }
  showUndoSnackBarOn(
    messenger,
    '${order.number} je v arhivu.',
    () => repo.unarchiveOrder(order.id),
  );
}

/// Restores an archived order to the workflow. No confirmation: an order
/// archived by mistake must be back with one tap, and restoring is harmless —
/// the order is exactly as it was. Undo archives it again.
void restoreFromArchive(
  BuildContext context,
  Repository repo,
  WorkOrder order,
) {
  if (!repo.unarchiveOrder(order.id)) return;
  showUndoSnackBar(
    context,
    '${order.number} je spet v poteku.',
    () => repo.archiveOrder(order.id),
  );
}
