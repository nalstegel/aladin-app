import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../orders/new_order_screen.dart';
import '../orders/pickup_sheet.dart';
import '../widgets/common.dart';
import '../widgets/delivery_fee_stepper.dart';
import '../widgets/pickup_window_picker.dart';

/// Hiter vnos naročila na vrhu Danes (v3 spec §1, V8 §1): telefon → ime →
/// Pripeljano/Naš prevzem → regija → število kosov → Ustvari naročilo. To je
/// edino glavno mesto za ustvarjanje naročil; na strani Naročila ni + gumba.
///
/// Za vse ostalo (B2B, opombe, poljubni datumi) ostaja polni obrazec za Novo
/// naročilo, dosegljiv iz povezave na dnu tega kartona.
class QuickOrderCard extends ConsumerStatefulWidget {
  const QuickOrderCard({super.key});

  @override
  ConsumerState<QuickOrderCard> createState() => _QuickOrderCardState();
}

class _QuickOrderCardState extends ConsumerState<QuickOrderCard> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _street = TextEditingController();
  final _postal = TextEditingController(text: '1000');
  final _city = TextEditingController(text: 'Ljubljana');

  Customer? _customer;
  // Uporabnik je izrecno potrdil "nova stranka" — skrije seznam ujemanj po
  // telefonu, tudi če se telefon delno ujema z obstoječo stranko.
  bool _forceNewCustomer = false;
  OrderChannel _channel = OrderChannel.dropoff;
  OrderLocation _location = OrderLocation.ljubljana;
  int _itemCount = 1;
  double _deliveryFee = 0;
  DateTime _pickupDate = DateTime.now();
  TimeOfDay? _pickupStart;
  TimeOfDay? _pickupEnd;

  @override
  void initState() {
    super.initState();
    _postal.addListener(_onPostalChanged);
    _city.addListener(_onCityChanged);
  }

  bool _linkingAddress = false;
  void _onPostalChanged() {
    if (_linkingAddress) return;
    final city = cityForPostalCode(_postal.text);
    if (city == null || _city.text.trim().isNotEmpty) return;
    _linkingAddress = true;
    _city.text = city;
    _linkingAddress = false;
  }

  void _onCityChanged() {
    if (_linkingAddress) return;
    final postal = postalCodeForCity(_city.text);
    if (postal == null || _postal.text.trim().isNotEmpty) return;
    _linkingAddress = true;
    _postal.text = postal;
    _linkingAddress = false;
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    _street.dispose();
    _postal.dispose();
    _city.dispose();
    super.dispose();
  }

  bool get _isNewCustomer => _customer == null;

  bool get _canSubmit {
    if (_customer != null) return true;
    return _phone.text.trim().isNotEmpty && _name.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.bolt, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Hiter vnos naročila',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          // Obrazec je vedno odprt — to je glavno mesto za sprejem naročila.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _form(),
          ),
        ],
      ),
    );
  }

  Widget _form() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 12),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => setState(() => _forceNewCustomer = false),
          decoration: const InputDecoration(
            labelText: 'Telefon',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        const SizedBox(height: 10),
        _customerSection(),
        const SizedBox(height: 12),
        const Text('Način', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<OrderChannel>(
          segments: const [
            ButtonSegment(
              value: OrderChannel.dropoff,
              icon: Icon(Icons.storefront_outlined, size: 16),
              label: Text('Pripeljano'),
            ),
            ButtonSegment(
              value: OrderChannel.delivery,
              icon: Icon(Icons.local_shipping_outlined, size: 16),
              label: Text('Naš prevzem'),
            ),
          ],
          selected: {_channel},
          onSelectionChanged: (s) => setState(() => _channel = s.first),
        ),
        const SizedBox(height: 12),
        const Text('Regija', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<OrderLocation>(
          segments: [
            for (final l in OrderLocation.values)
              ButtonSegment(
                value: l,
                label: Text(l.code, maxLines: 1, softWrap: false),
              ),
          ],
          // Brez kljukice — sicer oznaka nima prostora in se prelomi.
          showSelectedIcon: false,
          selected: {_location},
          onSelectionChanged: (s) => setState(() => _location = s.first),
        ),
        if (_channel == OrderChannel.delivery && _isNewCustomer) ...[
          const SizedBox(height: 12),
          const Text('Naslov', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          TextField(
            controller: _street,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ulica in hišna št.'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _postal,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Pošta'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Kraj'),
                ),
              ),
            ],
          ),
        ],
        if (_channel == OrderChannel.delivery) ...[
          const SizedBox(height: 12),
          const Text('Termin prevzema', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
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
          const SizedBox(height: 12),
          DeliveryFeeStepper(
            value: _deliveryFee,
            onChanged: (v) => setState(() => _deliveryFee = v),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Število kosov', style: TextStyle(fontSize: 14)),
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed:
                      _itemCount > 1 ? () => setState(() => _itemCount--) : null,
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '$_itemCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed:
                      _itemCount < 50 ? () => setState(() => _itemCount++) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _canSubmit ? _submit : null,
            icon: const Icon(Icons.check),
            label: Text('Ustvari naročilo · ${Fmt.pieces(_itemCount)}'),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NewOrderScreen()),
            ),
            child: const Text('Polni obrazec (B2B, opombe, drugi termini)'),
          ),
        ),
      ],
    );
  }

  Widget _customerSection() {
    if (_customer != null) {
      final c = _customer!;
      return AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Text(
                c.initials,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                c.name,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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

    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    final all = ref.watch(repositoryProvider).customers;
    final matches = digits.length < 3 || _forceNewCustomer
        ? const <Customer>[]
        : all
            .where((c) => c.phone.replaceAll(RegExp(r'\D'), '').contains(digits))
            .take(3)
            .toList();

    if (matches.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in matches) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              onTap: () => setState(() => _customer = c),
              child: Row(
                children: [
                  const Icon(Icons.person_outline,
                      size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${c.name} · ${c.phone}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
          ],
          TextButton.icon(
            onPressed: () => setState(() => _forceNewCustomer = true),
            icon: const Icon(Icons.person_add_alt, size: 16),
            label: const Text('To je nova stranka'),
          ),
        ],
      );
    }

    return TextField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        labelText: 'Ime nove stranke',
        prefixIcon: Icon(Icons.person_add_alt),
      ),
    );
  }

  void _submit() {
    final repo = ref.read(repositoryProvider.notifier);
    final handover = _channel == OrderChannel.dropoff
        ? HandoverMode.customerCollects
        : HandoverMode.weDeliver;

    final customer = _customer ??
        repo.createCustomer(
          type: CustomerType.private,
          name: _name.text,
          phone: _phone.text,
          address: _channel == OrderChannel.delivery ? _street.text : '',
          city: _channel == OrderChannel.delivery ? _city.text : '',
          postalCode: _channel == OrderChannel.delivery ? _postal.text : '',
        );

    final pickupAt = _channel == OrderChannel.delivery && _pickupStart != null
        ? DateTime(_pickupDate.year, _pickupDate.month, _pickupDate.day,
            _pickupStart!.hour, _pickupStart!.minute)
        : null;
    final pickupWindowEnd =
        _channel == OrderChannel.delivery && _pickupEnd != null
            ? DateTime(_pickupDate.year, _pickupDate.month, _pickupDate.day,
                _pickupEnd!.hour, _pickupEnd!.minute)
            : null;

    final order = repo.createOrder(
      customer: customer,
      location: _location,
      channel: _channel,
      handover: handover,
      itemCount: _itemCount,
      pickupAt: pickupAt,
      pickupWindowEnd: pickupWindowEnd,
      dueAt: DateTime.now().add(const Duration(days: 7)),
      deliveryFee: _channel == OrderChannel.delivery ? _deliveryFee : 0,
    );

    setState(() {
      _phone.clear();
      _name.clear();
      _street.clear();
      _postal.text = '1000';
      _city.text = 'Ljubljana';
      _customer = null;
      _forceNewCustomer = false;
      _channel = OrderChannel.dropoff;
      _itemCount = 1;
      _deliveryFee = 0;
      _pickupStart = null;
      _pickupEnd = null;
    });

    // Pripeljano: najprej hiter korak prevzema, nato etikete (V8 §2).
    continueAfterOrderCreated(context, order);
  }
}
