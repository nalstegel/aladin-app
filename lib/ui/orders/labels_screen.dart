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
///
/// Tisk ali ponatis etikete NIKOLI ne spremeni statusa (V8 §2) — kosi gredo
/// v Čaka pranje samo s potrditvijo prevzema.
class LabelsScreen extends ConsumerStatefulWidget {
  const LabelsScreen({
    super.key,
    required this.orderId,
    this.isNew = false,
    this.onlyItemId,
  });

  final String orderId;
  final bool isNew;

  /// Če je podan, je ob odprtju izbran samo ta kos (individualni ponatis).
  final String? onlyItemId;

  @override
  ConsumerState<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends ConsumerState<LabelsScreen> {
  bool _printing = false;

  /// Izbrani kosi za "Natisni izbrane". null = še ni dotika, torej vsi (ali
  /// samo [LabelsScreen.onlyItemId]).
  Set<String>? _selected;

  Set<String> _selection(List<RugItem> items) {
    final s = _selected;
    if (s != null) return s;
    final only = widget.onlyItemId;
    if (only != null && items.any((i) => i.id == only)) return {only};
    return {for (final i in items) i.id};
  }

  void _toggle(RugItem item, List<RugItem> items) {
    final current = {..._selection(items)};
    if (!current.remove(item.id)) current.add(item.id);
    setState(() => _selected = current);
  }

  Future<void> _print(WorkOrder order, List<RugItem> toPrint) async {
    if (toPrint.isEmpty) return;
    setState(() => _printing = true);
    try {
      final kind = labelKindFor(
        location: order.location,
        channel: order.channel,
      );
      final zpl = toPrint
          .map((item) => buildLabelZpl(
                kind: kind,
                itemId: item.id,
                orderId: order.id,
                pieceLabel: item.pieceLabel,
                customerName: order.customerName,
                phone: Fmt.phone(order.customerPhone),
                regionCode: order.location.code,
              ))
          .join();
      await ref.read(zebraPrinterServiceProvider).print(zpl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${toPrint.length} etiket poslanih na tiskalnik.')),
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
    final selection = _selection(items);
    final selectedItems = [
      for (final i in items)
        if (selection.contains(i.id)) i,
    ];
    final kind = labelKindFor(location: order.location, channel: order.channel);

    final spinner = const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );

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
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 130),
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
                        const Text(
                          'Natisni etikete in jih pripni na preproge. '
                          'Tisk ne spremeni statusa naročila.',
                          style: TextStyle(
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
          SectionHeader(
            'Predogled',
            subtitle: items.length > 1
                ? 'Tapni etiketo za izbiro — ponatis posameznega kosa.'
                : null,
            trailing: items.length > 1
                ? Text(
                    'Izbrano ${selectedItems.length}/${items.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  )
                : null,
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // Nalepka je ležeča, 60×40mm. Pri enem ali dveh kosih je
              // predogled velik, da se besedilo bere.
              crossAxisCount: items.length <= 2 ? 1 : 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: labelWidthDots / labelHeightDots,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final item = items[i];
              final selected = selection.contains(item.id);
              return GestureDetector(
                onTap: items.length > 1 ? () => _toggle(item, items) : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: selected ? 1 : 0.45,
                        child: _LabelPreview(
                          order: order,
                          item: item,
                          kind: kind,
                        ),
                      ),
                    ),
                    if (items.length > 1)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 22,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              );
            },
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
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
                  // Print all: cela etiketa naročila, vedno na voljo.
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _printing ? null : () => _print(order, items),
                      icon: _printing ? spinner : const Icon(Icons.print),
                      label: Text(
                        items.length == 1
                            ? 'Natisni'
                            : 'Natisni vse · ${items.length}',
                      ),
                    ),
                  ),
                ],
              ),
              if (items.length > 1) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _printing || selectedItems.isEmpty
                        ? null
                        : () => _print(order, selectedItems),
                    icon: const Icon(Icons.print_outlined),
                    label: Text('Natisni izbrane · ${selectedItems.length}'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Predogled nalepke, narisan iz iste postavitve kot tisk (`buildLabelLayout`),
/// v pikah tiskalnika (480×320) in pomanjšan. Zato se ne more razlikovati od
/// tega, kar se dejansko natisne.
class _LabelPreview extends StatelessWidget {
  const _LabelPreview({
    required this.order,
    required this.item,
    required this.kind,
  });

  final WorkOrder order;
  final RugItem item;
  final LabelKind kind;

  @override
  Widget build(BuildContext context) {
    final layout = buildLabelLayout(
      kind: kind,
      itemId: item.id,
      orderId: order.id,
      pieceLabel: item.pieceLabel,
      customerName: order.customerName,
      phone: Fmt.phone(order.customerPhone),
      regionCode: order.location.code,
    );

    TextAlign align(String a) => switch (a) {
      'R' => TextAlign.right,
      'C' => TextAlign.center,
      _ => TextAlign.left,
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: labelWidthDots.toDouble(),
          height: labelHeightDots.toDouble(),
          child: Stack(
            children: [
              Positioned(
                left: LabelLayout.qrX.toDouble(),
                top: LabelLayout.qrY.toDouble(),
                width: LabelLayout.qrSize.toDouble(),
                height: LabelLayout.qrSize.toDouble(),
                child: QrImageView(
                  data: layout.qrData,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                ),
              ),
              for (final f in layout.fields)
                Positioned(
                  left: f.x.toDouble(),
                  top: f.y.toDouble(),
                  width: f.w.toDouble(),
                  child: Text(
                    f.text,
                    maxLines: f.maxLines,
                    overflow: TextOverflow.clip,
                    textAlign: align(f.align),
                    style: TextStyle(
                      fontSize: f.size * 0.9,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111111),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
