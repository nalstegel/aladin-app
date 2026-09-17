import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/zpl.dart';
import '../../data/providers.dart';
import '../../data/zebra_printer.dart';
import '../../models/order.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';
import 'order_detail_screen.dart';

/// Etikete za posamezne kose. QR vsebuje ID kosa, npr. "LJ-001-2",
/// zato skeniranje vedno odpre točno to preprogo.
class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({super.key, required this.orderId, this.isNew = false});

  final String orderId;
  final bool isNew;

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  bool _printing = false;

  Future<void> _print(WorkOrder order, List<RugItem> items) async {
    setState(() => _printing = true);
    try {
      final zpl = items
          .map((item) => buildLabelZpl(
                orderId: order.number,
                customerName: order.customerName,
                dimensions: Fmt.dimensions(item.widthCm, item.lengthCm),
                itemId: item.id,
              ))
          .join();
      await ref.read(zebraPrinterServiceProvider).print(zpl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${items.length} etiket poslanih na tiskalnik.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tiskanje ni uspelo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(repositoryProvider);
    final order = state.order(widget.orderId);
    if (order == null) {
      return const Scaffold(body: Center(child: Text('Naročilo ne obstaja')));
    }
    final items = state.itemsOf(widget.orderId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Etikete ${order.number}'),
        automaticallyImplyLeading: !widget.isNew,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (widget.isNew)
            AppCard(
              borderColor: AppColors.ready.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.ready, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Naročilo ${order.number} ustvarjeno',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Natisni etikete in jih pripni na preproge.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SectionHeader('Predogled'),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => AspectRatio(
              // Nalepka je 60×40mm — širša kot visoka, zato predogled sledi
              // isti postavitvi (QR levo, besedilo desno) kot pravi izpis.
              aspectRatio: 1.5,
              child: _LabelPreview(order: order, item: items[i]),
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
          child: Row(
            children: [
              if (widget.isNew)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            OrderDetailScreen(orderId: widget.orderId),
                      ),
                    ),
                    child: const Text('Odpri naročilo'),
                  ),
                ),
              if (widget.isNew) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _printing ? null : () => _print(order, items),
                  icon: _printing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.print),
                  label: const Text('Natisni'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelPreview extends StatelessWidget {
  const _LabelPreview({required this.order, required this.item});

  final WorkOrder order;
  final RugItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      // Postavitev sledi pravi nalepki: QR levo, besedilo desno, da izkoristi
      // daljšo (60mm) stranico namesto da bi vse skladala navpično.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: QrImageView(
              data: item.id,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.number,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.customerName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  Fmt.dimensions(item.widthCm, item.lengthCm),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
