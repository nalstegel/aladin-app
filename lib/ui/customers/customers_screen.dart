import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/customer.dart';
import '../../models/enums.dart';
import '../widgets/common.dart';
import 'customer_detail_screen.dart';
import 'customer_form.dart';

/// CRM, ki se gradi sam iz naročil.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _search = TextEditingController();
  CustomerType? _filter;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final query = _search.text.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'\D'), '');

    final list = state.customers.where((c) {
      if (_filter != null && c.type != _filter) return false;
      if (query.isEmpty) return true;
      return c.name.toLowerCase().contains(query) ||
          c.email.toLowerCase().contains(query) ||
          c.city.toLowerCase().contains(query) ||
          (digits.isNotEmpty &&
              c.phone.replaceAll(RegExp(r'\D'), '').contains(digits));
    }).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            PageHeader(
              'Stranke',
              trailing: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nova stranka'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SearchField(
                controller: _search,
                hint: 'Išči po imenu, telefonu ali e-pošti',
                onChanged: (_) => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  FilterPill(
                    label: 'Vse',
                    selected: _filter == null,
                    onTap: () => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  FilterPill(
                    label: 'Osebe',
                    selected: _filter == CustomerType.private,
                    onTap: () =>
                        setState(() => _filter = CustomerType.private),
                  ),
                  const SizedBox(width: 8),
                  FilterPill(
                    label: 'Podjetja',
                    selected: _filter == CustomerType.company,
                    onTap: () =>
                        setState(() => _filter = CustomerType.company),
                  ),
                ],
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'Ni zadetkov',
                      message: 'Nova stranka se doda ob sprejemu naročila.',
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _tile(list[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Customer c) {
    final state = ref.watch(repositoryProvider);
    final open = state.ordersOf(c.id).where((o) => o.status.isOpen).length;
    final color =
        c.isCompany ? AppColors.awaitingPickup : AppColors.primary;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomerDetailScreen(customerId: c.id),
        ),
      ),
      child: Row(
        children: [
          AvatarCircle(c.name, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [c.phone, c.city].where((e) => e.isNotEmpty).join(' · '),
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
          if (open > 0) ...[
            const SizedBox(width: 8),
            Text(
              '$open aktivn${open == 1 ? "o" : "a"}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
        ],
      ),
    );
  }
}
