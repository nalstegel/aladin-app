import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../orders/new_order_screen.dart';
import '../orders/order_card.dart';
import '../widgets/common.dart';
import 'customer_form.dart';

/// Profil stranke: aktivna naročila in celotna zgodovina — CRM, ki nastane
/// sam od sebe iz vsakodnevnega dela.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final c = state.customer(customerId);
    if (c == null) {
      return const Scaffold(body: Center(child: Text('Stranka ne obstaja')));
    }
    final orders = state.ordersOf(customerId);
    final open = orders.where((o) => o.status.isOpen).toList();
    final past = orders.where((o) => !o.status.isOpen).toList();

    final totalSpent = past.fold<double>(
      0,
      (s, o) => s + state.orderTotal(o.id),
    );
    final totalItems =
        orders.fold<int>(0, (s, o) => s + state.itemsOf(o.id).length);
    final totalM2 = orders.fold<double>(
      0,
      (s, o) => s + state.orderM2(o.id),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CustomerFormScreen(existing: c),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          AppCard(
            child: Column(
              children: [
                DetailRow('Tip', c.type.label),
                if (c.phone.isNotEmpty) DetailRow('Telefon', c.phone),
                if (c.email.isNotEmpty) DetailRow('E-pošta', c.email),
                if (c.fullAddress.isNotEmpty)
                  DetailRow('Naslov', c.fullAddress),
                if (c.taxId.isNotEmpty) DetailRow('Davčna', c.taxId),
                if (c.contactPerson.isNotEmpty)
                  DetailRow('Kontakt', c.contactPerson),
                if (c.defaultDiscountPercent > 0)
                  DetailRow('Dogovorjen popust',
                      '${c.defaultDiscountPercent.toStringAsFixed(0)} %'),
                DetailRow('Stranka od', Fmt.date(c.createdAt)),
              ],
            ),
          ),
          if (c.notes.isNotEmpty) ...[
            const SizedBox(height: 10),
            AppCard(
              borderColor: AppColors.awaitingWash.withValues(alpha: 0.4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.sticky_note_2_outlined,
                      size: 18, color: AppColors.awaitingWash),
                  const SizedBox(width: 10),
                  Expanded(
                    child:
                        Text(c.notes, style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],
          const SectionHeader('Skupaj do zdaj'),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  value: '${orders.length}',
                  label: 'naročil',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: '$totalItems',
                  label: 'preprog',
                  color: AppColors.drying,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: StatTile(
                  value: totalM2.toStringAsFixed(0),
                  label: 'm² opranih',
                  color: AppColors.finishing,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppCard(
            child: DetailRow(
              'Vrednost zaključenih',
              Fmt.money(totalSpent),
              strong: true,
            ),
          ),
          SectionHeader('Aktivna naročila (${open.length})'),
          if (open.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Ni aktivnih naročil.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            )
          else
            for (final o in open) ...[
              OrderCard(o),
              const SizedBox(height: 8),
            ],
          SectionHeader('Zgodovina (${past.length})'),
          if (past.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Še ni zaključenih naročil.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            )
          else
            for (final o in past) ...[
              OrderCard(o),
              const SizedBox(height: 8),
            ],
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
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NewOrderScreen(
                  initialChannel: c.isCompany
                      ? OrderChannel.b2b
                      : OrderChannel.dropoff,
                  presetCustomer: c,
                ),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Novo naročilo za to stranko'),
          ),
        ),
      ),
    );
  }
}
