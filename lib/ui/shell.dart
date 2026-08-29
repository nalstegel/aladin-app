import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/navigation.dart';
import 'customers/customers_screen.dart';
import 'dashboard/dashboard_screen.dart';
import 'more/more_screen.dart';
import 'orders/orders_screen.dart';
import 'scanner/scanner_screen.dart';

/// Ogrodje z ročno izdelano spodnjo vrstico — sredinski gumb je skener,
/// ker je to dejanje, ki se v obratu ponovi največkrat.
///
/// Kamera skenerja teče samo, kadar je njegov zavihek izbran (glej `active`),
/// sicer bi praznila baterijo ves čas, ko je aplikacija odprta.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellTabProvider);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          const DashboardScreen(),
          const OrdersScreen(),
          ScannerScreen(active: index == shellTabScanner),
          const CustomersScreen(),
          const MoreScreen(),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: index,
        onSelect: (i) => ref.read(shellTabProvider.notifier).state = i,
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              _Item(
                icon: Icons.today_outlined,
                activeIcon: Icons.today,
                label: 'Danes',
                selected: index == 0,
                onTap: () => onSelect(0),
              ),
              _Item(
                icon: Icons.receipt_long_outlined,
                activeIcon: Icons.receipt_long,
                label: 'Naročila',
                selected: index == 1,
                onTap: () => onSelect(1),
              ),
              Expanded(
                child: Center(
                  child: GestureDetector(
                    onTap: () => onSelect(shellTabScanner),
                    child: Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
              _Item(
                icon: Icons.people_alt_outlined,
                activeIcon: Icons.people_alt,
                label: 'Stranke',
                selected: index == 3,
                onTap: () => onSelect(3),
              ),
              _Item(
                icon: Icons.more_horiz,
                activeIcon: Icons.more_horiz,
                label: 'Več',
                selected: index == 4,
                onTap: () => onSelect(4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : AppColors.textMuted;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? activeIcon : icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
