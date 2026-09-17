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

const _presetWindows = [
  (TimeOfDay(hour: 8, minute: 0), TimeOfDay(hour: 10, minute: 0)),
  (TimeOfDay(hour: 10, minute: 0), TimeOfDay(hour: 12, minute: 0)),
  (TimeOfDay(hour: 12, minute: 0), TimeOfDay(hour: 14, minute: 0)),
  (TimeOfDay(hour: 14, minute: 0), TimeOfDay(hour: 16, minute: 0)),
  (TimeOfDay(hour: 16, minute: 0), TimeOfDay(hour: 18, minute: 0)),
];

/// Hitro časovno okno namesto klasičnega time pickerja (v3 spec §1):
/// 8-10, 10-12, 12-14, 14-16, 16-18, Drugo (z ločenima poljema Od/Do).
/// Datum je ločen od okna, izbran zgoraj.
class PickupWindowPicker extends StatefulWidget {
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

  @override
  State<PickupWindowPicker> createState() => _PickupWindowPickerState();
}

class _PickupWindowPickerState extends State<PickupWindowPicker> {
  bool _custom = false;

  @override
  void initState() {
    super.initState();
    if (widget.start != null &&
        !_presetWindows.any((w) => w.$1 == widget.start && w.$2 == widget.end)) {
      _custom = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _pickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.event_outlined,
                    size: 18, color: AppColors.textMuted),
                const SizedBox(width: 8),
                const Text('Datum prevzema', style: TextStyle(fontSize: 14)),
                const Spacer(),
                Text(
                  Fmt.dateShort(widget.date),
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
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final w in _presetWindows)
              ChoiceChip(
                label: Text('${_fmt(w.$1)}-${_fmt(w.$2)}'),
                selected: !_custom &&
                    widget.start == w.$1 &&
                    widget.end == w.$2,
                onSelected: (_) {
                  setState(() => _custom = false);
                  widget.onWindowChanged(w.$1, w.$2);
                },
              ),
            ChoiceChip(
              label: const Text('Drugo'),
              selected: _custom,
              onSelected: (_) => setState(() => _custom = true),
            ),
          ],
        ),
        if (_custom) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _timeField('Od', widget.start, true)),
              const SizedBox(width: 10),
              Expanded(child: _timeField('Do', widget.end, false)),
            ],
          ),
        ],
      ],
    );
  }

  String _fmt(TimeOfDay t) => '${t.hour}:${t.minute.toString().padLeft(2, '0')}'
      .replaceAll(':00', '');

  Widget _timeField(String label, TimeOfDay? value, bool isStart) {
    return OutlinedButton(
      onPressed: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: value ?? const TimeOfDay(hour: 8, minute: 0),
        );
        if (picked == null) return;
        if (isStart) {
          widget.onWindowChanged(picked, widget.end ?? picked);
        } else {
          widget.onWindowChanged(widget.start ?? picked, picked);
        }
      },
      child: Text(
        value == null ? label : '$label: ${_fmt(value)}',
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.date,
      firstDate: now.subtract(const Duration(days: 7)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) widget.onDateChanged(picked);
  }
}
