import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../customers/customer_form.dart';
import '../widgets/common.dart';
import '../widgets/pickup_window_picker.dart';
import 'labels_screen.dart';

/// Sprejem naročila. Isti obrazec za vse tri kanale — razlikujejo se
/// samo termini in način predaje.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({
    super.key,
    this.initialChannel = OrderChannel.dropoff,
    this.presetCustomer,
  });

  /// Kanal ni več zavihek, zato ga obrazec le predlaga — najpogostejši je
  /// osebni prevzem, delavec pa ga tu tudi spremeni.
  final OrderChannel initialChannel;
  final Customer? presetCustomer;

  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  OrderLocation _location = OrderLocation.ljubljana;
  late OrderChannel _channel = widget.initialChannel;
  late HandoverMode _handover = _defaultHandover(widget.initialChannel);
  Customer? _customer;
  int _itemCount = 1;
  DateTime _pickupDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay? _pickupStart;
  TimeOfDay? _pickupEnd;
  DateTime? _deliveryAt;
  DateTime? _dueAt;
  final _search = TextEditingController();
  final _notes = TextEditingController();

  static HandoverMode _defaultHandover(OrderChannel c) =>
      c == OrderChannel.dropoff
          ? HandoverMode.customerCollects
          : HandoverMode.weDeliver;

  @override
  void initState() {
    super.initState();
    _customer = widget.presetCustomer;
    _dueAt = DateTime.now().add(const Duration(days: 7));
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
      appBar: AppBar(title: const Text('Novo naročilo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          const SectionHeader('Območje'),
          SegmentedButton<OrderLocation>(
            segments: [
              for (final l in OrderLocation.values)
                ButtonSegment(value: l, label: Text(l.label)),
            ],
            selected: {_location},
            onSelectionChanged: (s) => setState(() => _location = s.first),
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
            onSelectionChanged: (s) => setState(() {
              _channel = s.first;
              _handover = _defaultHandover(_channel);
            }),
          ),
          const SectionHeader('Stranka'),
          _customerSection(),
          const SectionHeader('Število kosov'),
          _counter(),
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
            label: Text(
              _customer == null
                  ? 'Najprej izberi stranko'
                  : 'Ustvari naročilo · ${Fmt.pieces(_itemCount)}',
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerSection() {
    if (_customer != null) {
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
              onPressed: () => setState(() => _customer = null),
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
            onTap: () => setState(() => _customer = c),
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
    if (created != null) setState(() => _customer = created);
  }

  Widget _counter() {
    return AppCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Koliko kosov je stranka pustila?',
            style: TextStyle(fontSize: 14),
          ),
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: _itemCount > 1
                    ? () => setState(() => _itemCount--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  '$_itemCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _itemCount < 50
                    ? () => setState(() => _itemCount++)
                    : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ],
      ),
    );
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
    final order = repo.createOrder(
      customer: _customer!,
      location: _location,
      channel: _channel,
      handover: _handover,
      itemCount: _itemCount,
      pickupAt: _channel == OrderChannel.dropoff ? null : _pickupAt,
      pickupWindowEnd:
          _channel == OrderChannel.dropoff ? null : _pickupWindowEnd,
      deliveryAt:
          _handover == HandoverMode.weDeliver ? _deliveryAt : null,
      dueAt: _dueAt,
      notes: _notes.text,
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LabelsScreen(orderId: order.id, isNew: true),
      ),
    );
  }
}
