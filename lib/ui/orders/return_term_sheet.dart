import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/order.dart';
import '../widgets/pickup_window_picker.dart';

/// Izbran termin vračila. [start] == null pomeni, da je bil termin odstranjen.
class ReturnTermChoice {
  const ReturnTermChoice(this.start, this.end);

  const ReturnTermChoice.removed() : start = null, end = null;

  final DateTime? start;
  final DateTime? end;
}

/// Dogovor o vračilu (Pripravljeno → Rok → Uredi): ko stranko pokličemo in se
/// zmenimo za dan in časovno okno, ga vpišemo tu. Naročilo ostane v
/// Pripravljeno do tega dne, nato se samo pokaže v Dostavah — brez V kombi in
/// brez dodatnega planiranja.
///
/// Sheet samo vrne izbiro; zapiše jo klicatelj (`editReturnTerm` na podrobnostih
/// naročila, Novo / Uredi naročilo pri ustvarjanju).
class ReturnTermSheet extends StatefulWidget {
  const ReturnTermSheet({super.key, this.start, this.end});

  /// Že dogovorjen termin, če obstaja.
  final DateTime? start;
  final DateTime? end;

  static Future<ReturnTermChoice?> show(
    BuildContext context, {
    DateTime? start,
    DateTime? end,
  }) {
    return showModalBottomSheet<ReturnTermChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ReturnTermSheet(start: start, end: end),
    );
  }

  @override
  State<ReturnTermSheet> createState() => _ReturnTermSheetState();
}

class _ReturnTermSheetState extends State<ReturnTermSheet> {
  late DateTime _date;
  TimeOfDay? _from;
  TimeOfDay? _to;

  @override
  void initState() {
    super.initState();
    final start = widget.start;
    final end = widget.end;
    // Brez dogovora predlagamo jutri; uro mora uporabnik izbrati sam, da se
    // privzeto okno ne zapiše, ne da bi ga kdo videl.
    _date = start ?? DateTime.now().add(const Duration(days: 1));
    _from = start == null ? null : TimeOfDay.fromDateTime(start);
    _to = start == null
        ? null
        : TimeOfDay.fromDateTime(end ?? start);
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_date.year, _date.month, _date.day, t.hour, t.minute);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Termin vračila',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Naročilo ostane v Pripravljeno do izbranega dne, nato se samo '
                'pokaže v Dostavah.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),
              PickupWindowPicker(
                dateLabel: 'Datum vračila',
                firstDate: DateTime(now.year, now.month, now.day),
                date: _date,
                onDateChanged: (d) => setState(() => _date = d),
                start: _from,
                end: _to,
                onWindowChanged: (from, to) => setState(() {
                  _from = from;
                  _to = to;
                }),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  // Brez ure ni okna, zato ni kaj shraniti.
                  onPressed: _from == null
                      ? null
                      : () => Navigator.pop(
                            context,
                            ReturnTermChoice(_at(_from!), _at(_to ?? _from!)),
                          ),
                  child: Text(
                    _from == null ? 'Izberi uro' : 'Shrani termin',
                  ),
                ),
              ),
              if (widget.start != null)
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(
                      context,
                      const ReturnTermChoice.removed(),
                    ),
                    child: const Text(
                      'Odstrani termin',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Rok → Uredi" na podrobnostih naročila: izberi termin vračila in ga zapiši.
///
/// Termin velja samo za naročila, ki jih vračamo mi (`setReturnTerm`); klicatelj
/// ga ponudi samo tam.
Future<void> editReturnTerm(
  BuildContext context,
  WidgetRef ref,
  WorkOrder order,
) async {
  final choice = await ReturnTermSheet.show(
    context,
    start: order.deliveryAt,
    end: order.deliveryWindowEnd,
  );
  if (choice == null || !context.mounted) return;
  final repo = ref.read(repositoryProvider.notifier);
  if (!repo.setReturnTerm(order.id, start: choice.start, end: choice.end)) {
    return;
  }
  final start = choice.start;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        start == null
            ? 'Termin vračila odstranjen.'
            : 'Vračilo ${Fmt.dayWindow(start, choice.end)}.',
      ),
    ),
  );
}

/// Vrstica "Dogovorjeno vračilo" v obrazcih Novo / Uredi naročilo: ista izbira
/// termina kot na podrobnostih, samo da se shrani šele z naročilom.
class ReturnTermTile extends StatelessWidget {
  const ReturnTermTile({
    super.key,
    required this.start,
    required this.end,
    required this.onChanged,
  });

  final DateTime? start;
  final DateTime? end;
  final ValueChanged<ReturnTermChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: const Icon(
        Icons.home_outlined,
        size: 20,
        color: AppColors.textMuted,
      ),
      title: const Text('Dogovorjeno vračilo', style: TextStyle(fontSize: 14)),
      trailing: Text(
        start == null
            ? 'Izberi'
            : '${Fmt.dateShort(start)} ${Fmt.timeRange(start, end)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: start == null ? AppColors.textMuted : AppColors.primary,
        ),
      ),
      onTap: () async {
        final choice = await ReturnTermSheet.show(
          context,
          start: start,
          end: end,
        );
        if (choice != null) onChanged(choice);
      },
    );
  }
}
