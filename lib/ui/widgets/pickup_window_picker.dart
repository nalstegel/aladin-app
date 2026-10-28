import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';

/// Rezultat izbire termina: datum + časovno okno (začetek/konec).
class PickupWindow {
  const PickupWindow(this.date, this.start, this.end);

  final DateTime date;
  final TimeOfDay start;
  final TimeOfDay end;

  DateTime get startAt =>
      DateTime(date.year, date.month, date.day, start.hour, start.minute);
  DateTime get endAt =>
      DateTime(date.year, date.month, date.day, end.hour, end.minute);
}

/// Termin prevzema (QA v4 §8): datum v svoji vrstici, časovno okno pa v eni
/// kompaktni vrstici "Od [09:00]  Do [11:00]". Tap na uro odpre kolo z urami.
/// Enaka začetna in končna ura (npr. 08:00–08:00) je dovoljena in pomeni
/// točno dogovorjeno uro.
class PickupWindowPicker extends StatelessWidget {
  const PickupWindowPicker({
    super.key,
    required this.date,
    required this.onDateChanged,
    this.start,
    this.end,
    required this.onWindowChanged,
  });

  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;
  final TimeOfDay? start;
  final TimeOfDay? end;
  final void Function(TimeOfDay start, TimeOfDay end) onWindowChanged;

  static const _defaultStart = TimeOfDay(hour: 8, minute: 0);
  static const _defaultWindow = 2; // ur — ko izbereš "Od", "Do" sledi +2 h

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pickDate(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(
                  Icons.event_outlined,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 8),
                const Text('Datum prevzema', style: TextStyle(fontSize: 14)),
                const Spacer(),
                Text(
                  Fmt.dateShort(date),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.schedule, size: 18, color: AppColors.textMuted),
            const SizedBox(width: 8),
            const Text('Od', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: _timeButton(context, start, isStart: true)),
            const SizedBox(width: 14),
            const Text('Do', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 8),
            Expanded(child: _timeButton(context, end, isStart: false)),
          ],
        ),
      ],
    );
  }

  Widget _timeButton(
    BuildContext context,
    TimeOfDay? value, {
    required bool isStart,
  }) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      onPressed: () => _pickTime(context, isStart: isStart),
      child: Text(
        value == null ? '--:--' : _fmt(value),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  static String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  Future<void> _pickTime(BuildContext context, {required bool isStart}) async {
    final current = isStart
        ? (start ?? _defaultStart)
        : (end ?? start ?? _defaultStart);
    final picked = await showModalBottomSheet<TimeOfDay>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _TimeWheelSheet(title: isStart ? 'Od' : 'Do', initial: current),
    );
    if (picked == null) return;

    if (isStart) {
      // Če "Do" še ni izbran ali bi bil pred novim "Od", ga premaknemo.
      final newEnd = end == null
          ? TimeOfDay(
              hour: (picked.hour + _defaultWindow).clamp(0, 23),
              minute: picked.minute,
            )
          : (_minutes(end!) < _minutes(picked) ? picked : end!);
      onWindowChanged(picked, newEnd);
    } else {
      final s = start ?? picked;
      // "Do" ne more biti pred "Od"; enaka ura je dovoljena (točna ura).
      onWindowChanged(_minutes(picked) < _minutes(s) ? picked : s, picked);
    }
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) onDateChanged(picked);
  }
}

/// Preprosto kolo z urami (korak 30 min) in gumbom "Potrdi".
class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({required this.title, required this.initial});

  final String title;
  final TimeOfDay initial;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  static const _step = 30;
  late TimeOfDay _value = TimeOfDay(
    hour: widget.initial.hour,
    minute: widget.initial.minute - widget.initial.minute % _step,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            SizedBox(
              height: 180,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                minuteInterval: _step,
                initialDateTime: DateTime(
                  2000,
                  1,
                  1,
                  _value.hour,
                  _value.minute,
                ),
                onDateTimeChanged: (d) =>
                    _value = TimeOfDay(hour: d.hour, minute: d.minute),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _value),
                child: const Text('Potrdi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
