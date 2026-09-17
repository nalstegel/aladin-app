import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/address.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';

/// Obrazec za novo stranko ali urejanje obstoječe.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({
    super.key,
    this.existing,
    this.initialType = CustomerType.private,
    this.initialName = '',
  });

  final Customer? existing;
  final CustomerType initialType;
  final String initialName;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  late CustomerType _type;
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _postal;
  late final TextEditingController _city;
  late final TextEditingController _taxId;
  late final TextEditingController _contact;
  late final TextEditingController _discount;
  late final TextEditingController _notes;

  // Prepreči neskončno zanko med samodejnim izpolnjevanjem pošte/kraja.
  bool _linkingAddress = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _type = c?.type ?? widget.initialType;
    _name = TextEditingController(text: c?.name ?? widget.initialName);
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    // Nova stranka: privzeto 1000 Ljubljana (večina strank je od tam),
    // delavec ju lahko normalno spremeni za naročila izven Ljubljane.
    _postal = TextEditingController(text: c?.postalCode ?? (c == null ? '1000' : ''));
    _city = TextEditingController(text: c?.city ?? (c == null ? 'Ljubljana' : ''));
    _postal.addListener(_onPostalChanged);
    _city.addListener(_onCityChanged);
    _taxId = TextEditingController(text: c?.taxId ?? '');
    _contact = TextEditingController(text: c?.contactPerson ?? '');
    _discount = TextEditingController(
      text: (c?.defaultDiscountPercent ?? 0) == 0
          ? ''
          : c!.defaultDiscountPercent.toStringAsFixed(0),
    );
    _notes = TextEditingController(text: c?.notes ?? '');
  }

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
    for (final c in [
      _name,
      _phone,
      _email,
      _address,
      _postal,
      _city,
      _taxId,
      _contact,
      _discount,
      _notes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompany = _type == CustomerType.company;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'Nova stranka' : 'Uredi stranko'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
        children: [
          SegmentedButton<CustomerType>(
            segments: const [
              ButtonSegment(
                value: CustomerType.private,
                icon: Icon(Icons.person_outline, size: 16),
                label: Text('Oseba'),
              ),
              ButtonSegment(
                value: CustomerType.company,
                icon: Icon(Icons.apartment, size: 16),
                label: Text('Podjetje'),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SectionHeader('Osnovno'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: isCompany ? 'Naziv podjetja' : 'Ime in priimek',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefon'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-pošta'),
          ),
          const SectionHeader('Naslov'),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Ulica in hišna št.'),
          ),
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
          if (isCompany) ...[
            const SectionHeader('Podjetje'),
            TextField(
              controller: _taxId,
              decoration: const InputDecoration(labelText: 'Davčna številka'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _contact,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Kontaktna oseba'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _discount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dogovorjen popust',
                suffixText: '%',
                helperText: 'Samodejno predlagan pri končni obdelavi.',
              ),
            ),
          ],
          const SectionHeader('Opombe'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Npr. zvonec ne dela, dostava samo dopoldne …',
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
            onPressed: _name.text.trim().isEmpty ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('Shrani'),
          ),
        ),
      ),
    );
  }

  void _save() {
    final repo = ref.read(repositoryProvider.notifier);
    final discount =
        double.tryParse(_discount.text.replaceAll(',', '.')) ?? 0;

    if (widget.existing != null) {
      final updated = widget.existing!.copyWith(
        type: _type,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        address: _address.text.trim(),
        city: _city.text.trim(),
        postalCode: _postal.text.trim(),
        taxId: _taxId.text.trim(),
        contactPerson: _contact.text.trim(),
        defaultDiscountPercent: discount,
        notes: _notes.text.trim(),
      );
      repo.updateCustomer(updated);
      Navigator.pop(context, updated);
      return;
    }

    final created = repo.createCustomer(
      type: _type,
      name: _name.text,
      phone: _phone.text,
      email: _email.text,
      address: _address.text,
      city: _city.text,
      postalCode: _postal.text,
      taxId: _taxId.text,
      contactPerson: _contact.text,
      defaultDiscountPercent: discount,
      notes: _notes.text,
    );
    Navigator.pop(context, created);
  }
}
