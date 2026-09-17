import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../../models/order.dart';
import '../customers/customer_form.dart';
import '../widgets/common.dart';
import '../widgets/pickup_window_picker.dart';

/// Urejanje podatkov obstoječega naročila (stranka, kanal, termini,
/// opomba). Poslovalnica se ne spreminja — določila je predpono ID-ja ob
/// ustvarjanju in bi sprememba naredila neskladje z že natisnjenimi
/// etiketami. Število kosov ima svojo pot (gumb "Dodaj kos" na naročilu).
class EditOrderScreen extends ConsumerStatefulWidget {
  const EditOrderScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<EditOrderScreen> createState() => _EditOrderScreenState();
}

class _EditOrderScreenState extends ConsumerState<EditOrderScreen> {
  late WorkOrder _original;
  late OrderChannel _channel;
  late HandoverMode _handover;
  Customer? _customer;
  late DateTime _pickupDate;
  TimeOfDay? _pickupStart;
  TimeOfDay? _pickupEnd;
  DateTime? _deliveryAt;
  DateTime? _dueAt;
  final _search = TextEditingController();
  late final TextEditingController _notes;
  bool _pickingCustomer = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(repositoryProvider);
    final order = state.order(widget.orderId)!;
    _original = order;
    _channel = order.channel;
    _handover = order.handover;
    _customer = state.customer(order.customerId);
    _pickupDate = order.pickupAt ?? DateTime.now().add(const Duration(days: 1));
    _pickupStart = order.pickupAt == null
        ? null
        : TimeOfDay.fromDateTime(order.pickupAt!);
    _pickupEnd = order.pickupWindowEnd == null
        ? null
        : TimeOfDay.fromDateTime(order.pickupWindowEnd!);
    _deliveryAt = order.deliveryAt;
    _dueAt = order.dueAt;
    _notes = TextEditingController(text: order.notes);
  }

  @override
  void dispose() {
    _search.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Uredi naročilo ${_original.number}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          const SectionHeader('Poslovalnica'),
          AppCard(
            child: DetailRow('Poslovalnica', _original.location.label),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Poslovalnice po ustvarjanju naročila ni mogoče spremeniti.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          const SectionHeader('Način'),
          SegmentedButton<OrderChannel>(
            segments: [
              for (final c in OrderChannel.values)
                ButtonSegment(
                  value: c,
                  icon: Icon(AppIcons.forChannel(c), size: 16),
                  label: Text(c.short),
                ),
            ],
            selected: {_channel},
            onSelectionChanged: (s) => setState(() => _channel = s.first),
          ),
          const SectionHeader('Stranka'),
          _customerSection(),
          const SectionHeader('Termini'),
          _dates(),
          const SectionHeader('Opomba'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText:
                  'Npr. madež od vina na največji preprogi, zvonec ne dela …',
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: FilledButton.icon(
            onPressed: _customer == null ? null : _submit,
            icon: const Icon(Icons.check),
            label: const Text('Shrani spremembe'),
          ),
        ),
      ),
    );
  }

  Widget _customerSection() {
    if (!_pickingCustomer && _customer != null) {
      final c = _customer!;
      return AppCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                c.initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    [c.phone, c.fullAddress]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _pickingCustomer = true),
              child: const Text('Zamenjaj'),
            ),
          ],
        ),
      );
    }

    final query = _search.text.trim().toLowerCase();
    final all = ref.watch(repositoryProvider).customers;
    final wantCompany = _channel == OrderChannel.b2b;
    final matches = all
        .where((c) => c.isCompany == wantCompany)
        .where((c) =>
            query.isEmpty ||
            c.name.toLowerCase().contains(query) ||
            c.phone.replaceAll(' ', '').contains(query.replaceAll(' ', '')))
        .take(6)
        .toList();

    return Column(
      children: [
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: wantCompany
                ? 'Išči podjetje …'
                : 'Išči po imenu ali telefonu …',
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 8),
        for (final c in matches) ...[
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            onTap: () => setState(() {
              _customer = c;
              _pickingCustomer = false;
            }),
            child: Row(
              children: [
                Icon(
                  c.isCompany ? Icons.apartment : Icons.person_outline,
                  size: 18,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (c.phone.isNotEmpty)
                        Text(
                          c.phone,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.add_circle_outline,
                    size: 20, color: AppColors.primary),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _newCustomer,
          icon: const Icon(Icons.person_add_alt),
          label: Text(wantCompany ? 'Novo podjetje' : 'Nova stranka'),
        ),
      ],
    );
  }

  Future<void> _newCustomer() async {
    final created = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(
          initialType: _channel == OrderChannel.b2b
              ? CustomerType.company
              : CustomerType.private,
          initialName: _search.text.trim(),
        ),
      ),
    );
    if (created != null) {
      setState(() {
        _customer = created;
        _pickingCustomer = false;
      });
    }
  }

  Widget _dates() {
    return AppCard(
      child: Column(
        children: [
          if (_channel != OrderChannel.dropoff) ...[
            const Text(
              'Prevzem pri stranki',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            PickupWindowPicker(
              date: _pickupDate,
              onDateChanged: (d) => setState(() => _pickupDate = d),
              start: _pickupStart,
              end: _pickupEnd,
              onWindowChanged: (start, end) => setState(() {
                _pickupStart = start;
                _pickupEnd = end;
              }),
            ),
            const Divider(height: 24),
          ],
          _dateTile(
            'Obljubljen rok',
            _dueAt,
            (d) => setState(() => _dueAt = d),
            icon: Icons.event_available_outlined,
          ),
          if (_handover == HandoverMode.weDeliver)
            _dateTile(
              'Dogovorjeno vračilo',
              _deliveryAt,
              (d) => setState(() => _deliveryAt = d),
              icon: Icons.home_outlined,
            ),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Kdo poskrbi za vračilo?',
                  style: TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<HandoverMode>(
                style: SegmentedButton.styleFrom(
                  textStyle: const TextStyle(fontSize: 12),
                ),
                segments: const [
                  ButtonSegment(
                    value: HandoverMode.customerCollects,
                    label: Text('Stranka'),
                  ),
                  ButtonSegment(
                    value: HandoverMode.weDeliver,
                    label: Text('Mi'),
                  ),
                ],
                selected: {_handover},
                onSelectionChanged: (s) =>
                    setState(() => _handover = s.first),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dateTile(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onChanged, {
    required IconData icon,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(icon, size: 20, color: AppColors.textMuted),
      title: Text(label, style: const TextStyle(fontSize: 14)),
      trailing: Text(
        value == null ? 'Izberi' : '${Fmt.date(value)} ${Fmt.time(value)}',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: value == null ? AppColors.textMuted : AppColors.primary,
        ),
      ),
      onTap: () async {
        final now = DateTime.now();
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: now.subtract(const Duration(days: 7)),
          lastDate: now.add(const Duration(days: 365)),
        );
        if (date == null || !mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value ?? now),
        );
        onChanged(DateTime(
          date.year,
          date.month,
          date.day,
          time?.hour ?? 9,
          time?.minute ?? 0,
        ));
      },
    );
  }

  DateTime? get _pickupAt => _pickupStart == null
      ? null
      : DateTime(_pickupDate.year, _pickupDate.month, _pickupDate.day,
          _pickupStart!.hour, _pickupStart!.minute);

  DateTime? get _pickupWindowEnd => _pickupEnd == null
      ? null
      : DateTime(_pickupDate.year, _pickupDate.month, _pickupDate.day,
          _pickupEnd!.hour, _pickupEnd!.minute);

  void _submit() {
    final repo = ref.read(repositoryProvider.notifier);
    final includePickup = _channel != OrderChannel.dropoff;
    final pickupAt = includePickup ? _pickupAt : null;
    final pickupWindowEnd = includePickup ? _pickupWindowEnd : null;
    final deliveryAt =
        _handover == HandoverMode.weDeliver ? _deliveryAt : null;

    final updated = _original.copyWith(
      channel: _channel,
      handover: _handover,
      customerId: _customer!.id,
      customerName: _customer!.name,
      customerPhone: _customer!.phone,
      customerAddress: _customer!.fullAddress,
      pickupAt: pickupAt,
      clearPickupAt: pickupAt == null,
      pickupWindowEnd: pickupWindowEnd,
      clearPickupWindowEnd: pickupWindowEnd == null,
      deliveryAt: deliveryAt,
      clearDeliveryAt: deliveryAt == null,
      dueAt: _dueAt,
      clearDueAt: _dueAt == null,
      notes: _notes.text,
    );
    repo.updateOrder(updated);
    Navigator.pop(context);
  }
}
