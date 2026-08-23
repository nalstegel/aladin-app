import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../../models/return_proof.dart';
import '../scanner/scanner_screen.dart';
import '../widgets/common.dart';
import 'signature_screen.dart';

/// Varovalka pri vračilu: dokler niso poskenirani vsi kosi, se naročila
/// ne da zaključiti. Na koncu stranka podpiše prevzem.
class ReturnFlowScreen extends ConsumerStatefulWidget {
  const ReturnFlowScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ReturnFlowScreen> createState() => _ReturnFlowScreenState();
}

class _ReturnFlowScreenState extends ConsumerState<ReturnFlowScreen> {
  final _scanned = <String>{};

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final order = state.order(widget.orderId);
    if (order == null) {
      return const Scaffold(body: Center(child: Text('Naročilo ne obstaja')));
    }
    final items = state.itemsOf(widget.orderId);
    final allScanned =
        items.isNotEmpty && items.every((i) => _scanned.contains(i.id));
    final isAdmin = ref.watch(currentUserProvider)?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order.handover == HandoverMode.customerCollects
              ? 'Predaja ${order.number}'
              : 'Vračilo ${order.number}',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.customerName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.handover == HandoverMode.weDeliver
                      ? order.customerAddress
                      : order.customerPhone,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 12),
                ReadyProgress(
                  ready: _scanned.length,
                  total: items.length,
                  showLabel: false,
                ),
                const SizedBox(height: 8),
                Text(
                  '${_scanned.length}/${items.length} poskeniranih',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: allScanned
                        ? AppColors.ready
                        : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(
            'Kosi',
            subtitle: 'Poskeniraj vsak kos, preden ga izročiš.',
          ),
          for (final item in items) ...[
            AppCard(
              borderColor: _scanned.contains(item.id)
                  ? AppColors.ready.withValues(alpha: 0.6)
                  : null,
              child: Row(
                children: [
                  Icon(
                    _scanned.contains(item.id)
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: _scanned.contains(item.id)
                        ? AppColors.ready
                        : AppColors.border,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.index}/${item.ofTotal} · ${item.id}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          item.isMeasured
                              ? item.rugTypeName
                              : 'Brez podatkov o meri',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_scanned.contains(item.id) && isAdmin)
                    TextButton(
                      onPressed: () =>
                          setState(() => _scanned.add(item.id)),
                      child: const Text('Ročno'),
                    ),
                ],
              ),
            ),
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!allScanned)
                FilledButton.icon(
                  onPressed: _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Skeniraj kos'),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.ready,
                  ),
                  onPressed: () => _confirm(items.map((e) => e.id).toList()),
                  icon: const Icon(Icons.draw_outlined),
                  label: const Text('POTRDI VRAČILO'),
                ),
              if (isAdmin) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      _override(items.map((e) => e.id).toList()),
                  child: const Text(
                    'Zaključi brez podpisa (administrator)',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _scan() async {
    final state = ref.read(repositoryProvider);
    final valid = state.itemsOf(widget.orderId).map((e) => e.id).toSet();

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannerScreen(
          title: 'Skeniraj kose za vračilo',
          onResult: (id) {
            if (!valid.contains(id)) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.danger,
                  content: Text('$id ne spada v to naročilo!'),
                ),
              );
              return;
            }
            if (_scanned.contains(id)) return;
            setState(() => _scanned.add(id));
            final remaining = valid.length - _scanned.length;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: AppColors.ready,
                duration: const Duration(seconds: 1),
                content: Text(
                  remaining == 0
                      ? '$id ✓ — vsi kosi poskenirani'
                      : '$id ✓ — manjka še $remaining',
                ),
              ),
            );
            if (remaining == 0) Navigator.pop(context);
          },
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _confirm(List<String> itemIds) async {
    final state = ref.read(repositoryProvider);
    final order = state.order(widget.orderId)!;

    final result = await Navigator.push<SignatureResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SignatureScreen(
          orderNumber: order.number,
          itemCount: itemIds.length,
          defaultName: order.customerName,
        ),
      ),
    );
    if (result == null || !mounted) return;

    final user = ref.read(currentUserProvider);
    ref.read(repositoryProvider.notifier).completeReturn(
          widget.orderId,
          ReturnProof(
            returnedAt: DateTime.now(),
            userId: user?.id ?? '',
            userName: user?.name ?? '',
            scannedItemIds: itemIds,
            signatureBase64: result.signatureBase64,
            receivedByName: result.receivedByName,
          ),
        );

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.ready,
        content: Text('Naročilo ${order.number} zaključeno'),
      ),
    );
  }

  Future<void> _override(List<String> itemIds) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Zaključi brez podpisa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Naročilo se bo zaključilo brez podpisa stranke. Razlog se '
              'trajno zabeleži.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Razlog',
                hintText: 'Npr. dostava pred vrati po dogovoru',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Zaključi'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final user = ref.read(currentUserProvider);
    final state = ref.read(repositoryProvider);
    final order = state.order(widget.orderId)!;

    ref.read(repositoryProvider.notifier).completeReturn(
          widget.orderId,
          ReturnProof(
            returnedAt: DateTime.now(),
            userId: user?.id ?? '',
            userName: user?.name ?? '',
            scannedItemIds: _scanned.toList(),
            receivedByName: order.customerName,
            overrideReason: controller.text.trim().isEmpty
                ? 'Brez navedbe'
                : controller.text.trim(),
            overrideByName: user?.name,
          ),
        );

    if (!mounted) return;
    Navigator.pop(context);
  }
}
