import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../models/enums.dart';

/// Zapis zneska doplačila, npr. "10 €" ali "3 €/m²".
String formatExtraValue(double v, ExtraTemplate t) {
  final n = v.abs() == v.abs().roundToDouble()
      ? v.abs().toStringAsFixed(0)
      : v.abs().toStringAsFixed(2).replaceAll('.', ',');
  return '$n ${t.kind.label}';
}

/// Kompakten gumb za izbiro (vrsta, mera, doplačilo) — enak v Hitrem
/// obračunu in v prevzemu.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.primary : AppColors.text,
            ),
          ),
        ),
      ),
    );
  }
}

/// Postavka z izbiro (npr. Dlake 5 € / 10 €): delavec izbere znesek. Vrne
/// izbrano vrednost, 0 za "Odstrani" ali null, če je sheet zaprt brez izbire.
Future<double?> pickExtraChoice(
  BuildContext context,
  ExtraTemplate t, {
  double? current,
}) {
  return showModalBottomSheet<double>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                for (final v in t.choices) ...[
                  if (v != t.choices.first) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                        backgroundColor: current == v
                            ? AppColors.primary
                            : AppColors.primary.withValues(alpha: 0.75),
                      ),
                      onPressed: () => Navigator.pop(context, v),
                      child: Text(
                        formatExtraValue(v, t),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (current != null)
              TextButton(
                onPressed: () => Navigator.pop(context, 0.0),
                child: const Text('Odstrani'),
              ),
          ],
        ),
      ),
    ),
  );
}
