import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// Najmanjše in največje dostavno doplačilo ter korak (V8 §2).
const deliveryFeeMin = 10.0;
const deliveryFeeMax = 50.0;
const deliveryFeeStep = 5.0;

/// Izbira dostavnega doplačila: Brez, nato 10–50 € v korakih po 5 €.
class DeliveryFeeStepper extends StatelessWidget {
  const DeliveryFeeStepper({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// 0 = brez doplačila.
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final canDown = value > 0;
    final canUp = value < deliveryFeeMax;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Dostavno doplačilo', style: TextStyle(fontSize: 14)),
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Manj',
              onPressed: canDown
                  ? () => onChanged(
                        value <= deliveryFeeMin ? 0 : value - deliveryFeeStep,
                      )
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: Text(
                value == 0 ? 'Brez' : Fmt.money(value).replaceAll(',00', ''),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: value == 0 ? 15 : 18,
                  fontWeight: FontWeight.w800,
                  color: value == 0 ? AppColors.textMuted : AppColors.text,
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Več',
              onPressed: canUp
                  ? () => onChanged(
                        value == 0 ? deliveryFeeMin : value + deliveryFeeStep,
                      )
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}
