import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/alerts.dart';
import '../orders/order_detail_screen.dart';
import '../widgets/common.dart';

export '../../data/alerts.dart' show unreadAlertCountProvider;

/// Seznam obvestil. Ista obvestila pošlje tudi potisno sporočilo, tu pa so
/// zbrana za nazaj — tudi za telefon, ki obvestil nima vklopljenih.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  late final Set<String> _unreadOnOpen;

  @override
  void initState() {
    super.initState();
    // Katera so bila neprebrana ob odprtju — da jih lahko še prikažemo
    // označena, čeprav jih takoj označimo kot videna.
    final alerts = ref.read(alertsProvider);
    final seen = ref.read(seenAlertsProvider);
    _unreadOnOpen =
        alerts.where((a) => !seen.contains(a.id)).map((a) => a.id).toSet();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(seenAlertsProvider.notifier)
          .markSeen(alerts.map((a) => a.id).toSet());
    });
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Obvestila')),
      body: alerts.isEmpty
          ? const EmptyState(
              icon: Icons.notifications_none,
              title: 'Ni obvestil',
              message: 'Tu se pojavijo pripravljena naročila in zamude.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final a = alerts[i];
                final color = a.kind == AlertKind.overdue
                    ? AppColors.danger
                    : AppColors.ready;
                final unread = _unreadOnOpen.contains(a.id);

                return AppCard(
                  accent: color,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => OrderDetailScreen(orderId: a.orderId),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        a.kind == AlertKind.overdue
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        size: 20,
                        color: color,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    a.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: unread
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (unread)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.body,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              Fmt.relative(a.at),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
