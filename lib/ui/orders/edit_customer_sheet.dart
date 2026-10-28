import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/order.dart';

/// Direktno urejanje podatkov stranke na naročilu (V10 §1): ime / podjetje,
/// telefon in naslov, brez obvoza prek "Zamenjaj stranko". Zamenjava ostane
/// samo za dejansko menjavo na drugo stranko.
///
/// Popravek velja za stranko, ne samo za to naročilo: `Repository.updateCustomer`
/// uskladi podvojene podatke na vseh njenih naročilih, tako da napake v
/// telefonski številki ni treba popravljati dvakrat.
class EditCustomerSheet extends ConsumerStatefulWidget {
  const EditCustomerSheet({super.key, required this.orderId});

  final String orderId;

  static Future<void> show(BuildContext context, String orderId) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditCustomerSheet(orderId: orderId),
    );
  }

  @override
  ConsumerState<EditCustomerSheet> createState() => _EditCustomerSheetState();
}

class _EditCustomerSheetState extends ConsumerState<EditCustomerSheet> {
  late final WorkOrder _order;
  Customer? _customer;

  late final TextEditingController _name;
  late final TextEditingController _contact;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _postal;
  late final TextEditingController _city;

  // Prepreči neskončno zanko med samodejnim izpolnjevanjem pošte/kraja.
  bool _linking = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(repositoryProvider);
    _order = state.order(widget.orderId)!;
    _customer = state.customer(_order.customerId);
    final c = _customer;
    _name = TextEditingController(text: c?.name ?? _order.customerName);
    _contact = TextEditingController(text: c?.contactPerson ?? '');
    _phone = TextEditingController(text: c?.phone ?? _order.customerPhone);
    // Brez stranke v bazi je na voljo samo naslov, kot je zapisan na naročilu.
    _address = TextEditingController(
      text: c == null ? _order.customerAddress : c.address,
    );
    _postal = TextEditingController(text: c?.postalCode ?? '');
    _city = TextEditingController(text: c?.city ?? '');
    _postal.addListener(() {
      if (_linking) return;
      final city = cityForPostalCode(_postal.text);
      if (city == null || _city.text.trim().isNotEmpty) return;
      _linking = true;
      _city.text = city;
      _linking = false;
    });
    _city.addListener(() {
      if (_linking) return;
      final postal = postalCodeForCity(_city.text);
      if (postal == null || _postal.text.trim().isNotEmpty) return;
      _linking = true;
      _postal.text = postal;
      _linking = false;
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _contact, _phone, _address, _postal, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isCompany => _customer?.isCompany ?? false;
  bool get _valid => _name.text.trim().isNotEmpty;

  void _save() {
    final repo = ref.read(repositoryProvider.notifier);
    final c = _customer;
    if (c == null) {
      // Stranke ni več v bazi: popravimo samo zapis na naročilu.
      repo.updateOrder(
        _order.copyWith(
          customerName: _name.text.trim(),
          customerPhone: _phone.text.trim(),
          customerAddress: _address.text.trim(),
        ),
      );
    } else {
      repo.updateCustomer(
        c.copyWith(
          name: _name.text.trim(),
          contactPerson: _contact.text.trim(),
          phone: _phone.text.trim(),
          address: _address.text.trim(),
          postalCode: _postal.text.trim(),
          city: _city.text.trim(),
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Podatki stranke · ${_order.number}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _isCompany ? 'Podjetje' : 'Ime in priimek',
              ),
            ),
            if (_isCompany) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _contact,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Kontaktna oseba'),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ /\-]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Telefon',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _customer == null ? 'Naslov' : 'Ulica in hišna št.',
                prefixIcon: const Icon(Icons.place_outlined),
              ),
            ),
            if (_customer != null) ...[
              const SizedBox(height: 10),
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
            const SizedBox(height: 8),
            const Text(
              'Popravek velja za stranko in vsa njena naročila.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _valid ? _save : null,
              icon: const Icon(Icons.check),
              label: const Text('Shrani'),
            ),
          ],
        ),
      ),
    );
  }
}
