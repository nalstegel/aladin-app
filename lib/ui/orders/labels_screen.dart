import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/order.dart';
import '../../models/rug_item.dart';
import '../widgets/common.dart';
import 'order_detail_screen.dart';

/// Etikete za posamezne kose. QR vsebuje ID kosa, npr. "1847-2",
/// zato skeniranje vedno odpre točno to preprogo.
class LabelsScreen extends ConsumerWidget {
  const LabelsScreen({super.key, required this.orderId, this.isNew = false});

  final String orderId;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(repositoryProvider);
    final order = state.order(orderId);
    if (order == null) {
      return const Scaffold(body: Center(child: Text('Naročilo ne obstaja')));
    }
    final items = state.itemsOf(orderId);

    return Scaffold(
      appBar: AppBar(
        title: Text('Etikete ${order.number}'),
        automaticallyImplyLeading: !isNew,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
        children: [
          if (isNew)
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.82,
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
              if (isNew)
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderDetailScreen(orderId: orderId),
                      ),
                    ),
                    child: const Text('Odpri naročilo'),
                  ),
                ),
              if (isNew) const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Printing.layoutPdf(
                    onLayout: (format) => _buildPdf(order, items, format),
                    name: 'Etikete-${order.id}',
                  ),
                  icon: const Icon(Icons.print),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.customerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          Row(
            children: [
              Text(
                order.number,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'KOS ${item.index}/${item.ofTotal}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: QrImageView(
                data: item.id,
                size: 96,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              item.id,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
          ),
          Center(
            child: Text(
              Fmt.date(order.createdAt),
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A4 pola z mrežo etiket 3 × 6. Vsaka etiketa je samostojna, da jo lahko
/// izrežeš in pripneš na preprogo.
Future<Uint8List> _buildPdf(
  WorkOrder order,
  List<RugItem> items,
  PdfPageFormat format,
) async {
  final doc = pw.Document();

  pw.Widget label(RugItem item) => pw.Container(
        margin: const pw.EdgeInsets.all(4),
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.6, color: PdfColors.grey400),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              order.customerName,
              maxLines: 1,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(order.number, style: const pw.TextStyle(fontSize: 8)),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  color: PdfColors.black,
                  child: pw.Text(
                    'KOS ${item.index}/${item.ofTotal}',
                    style: pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Expanded(
              child: pw.Center(
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: item.id,
                  width: 62,
                  height: 62,
                  drawText: false,
                ),
              ),
            ),
            pw.Center(
              child: pw.Text(
                item.id,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

  const perPage = 18;
  for (var start = 0; start < items.length; start += perPage) {
    final chunk = items.skip(start).take(perPage).toList();
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: const pw.EdgeInsets.all(12),
        build: (context) => pw.GridView(
          crossAxisCount: 3,
          childAspectRatio: 0.78,
          children: chunk.map(label).toList(),
        ),
      ),
    );
  }

  return doc.save();
}
