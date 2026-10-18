import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/zpl.dart';
import '../../data/providers.dart';
import '../../data/zebra_printer.dart';
import '../../models/enums.dart';
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
                customerName: order.customerName,
                dimensions: item.isMeasured
                    ? Fmt.dimensions(item.widthCm, item.lengthCm)
                    : '',
                itemId: item.id,
                dropoff: order.channel == OrderChannel.dropoff,
                phone: Fmt.phone(order.customerPhone),
                pieceLabel: item.label,
              ))
          .join();
      await ref.read(zebraPrinterServiceProvider).print(zpl);
      // Natisnjene etikete pomenijo, da so preproge pri nas → Čaka pranje.
      ref.read(repositoryProvider.notifier).markLabelsPrinted(order.id);
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
        // Po ustvarjanju naročila zapre celoten postopek in vrne tja, od
        // koder je bilo naročilo ustvarjeno — brez odpiranja naročila.
        leading: widget.isNew
            ? IconButton(
                tooltip: 'Zapri',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            : null,
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
                          'Natisni etikete in jih pripni na preproge. '
                          'Dokler etikete niso natisnjene, naročilo '
                          'ostane v zavihku Naročila.',
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              // Nalepka je pokončna, 40×60mm.
              childAspectRatio: 40 / 60,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _LabelPreview(order: order, item: items[i]),
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
    // Postavitev sledi pravi nalepki (`buildLabelZpl`): QR na vrhu, pod njim
    // besedilo, ki je pri Pripeljano drugačno kot pri Dostavah.
    final dropoff = order.channel == OrderChannel.dropoff;
    final dims = item.isMeasured ? Fmt.dimensions(item.widthCm, item.lengthCm) : '';
    final phone = Fmt.phone(order.customerPhone);

    Widget text(String value, double size,
            {FontWeight weight = FontWeight.w600,
            int maxLines = 1,
            Color color = AppColors.text,
            double spacing = 0}) =>
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            value,
            textAlign: TextAlign.center,
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: size,
              fontWeight: weight,
              color: color,
              letterSpacing: spacing,
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.25,
            child: QrImageView(
              data: item.id,
              padding: EdgeInsets.zero,
            ),
          ),
          const SizedBox(height: 6),
          if (dropoff) ...[
            text(order.customerName, 14, weight: FontWeight.w800, maxLines: 2),
            if (phone.isNotEmpty) text(phone, 13, weight: FontWeight.w700),
            text(item.label, 15, weight: FontWeight.w800),
            text(item.id, 11, weight: FontWeight.w700, spacing: 1),
          ] else ...[
            text(item.id, 18, weight: FontWeight.w900),
            text(order.customerName, 12, maxLines: 2),
            if (dims.isNotEmpty) text(dims, 11, color: AppColors.textMuted),
          ],
        ],
      ),
    );
  }
}
