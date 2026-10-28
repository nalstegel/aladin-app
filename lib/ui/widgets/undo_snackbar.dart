import 'package:flutter/material.dart';

/// Kako dolgo je viden snackbar z Razveljavi (V10 §5: približno 4–6 s).
const undoSnackBarDuration = Duration(seconds: 5);

/// Snackbar z Razveljavi, ki izgine sam.
///
/// Flutter `SnackBar` z akcijo privzeto NE izgine (`persist` je takrat true),
/// zato je "LJ-084 je v kombiju. Razveljavi" ostal čez več zaslonov. Undo je
/// samo kratka varovalka, ne trajno obvestilo.
void showUndoSnackBar(
  BuildContext context,
  String message,
  VoidCallback onUndo,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: undoSnackBarDuration,
        persist: false,
        action: SnackBarAction(label: 'Razveljavi', onPressed: onUndo),
      ),
    );
}
