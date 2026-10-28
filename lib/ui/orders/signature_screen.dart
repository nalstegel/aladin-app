import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../../core/theme.dart';

/// Rezultat podpisnega zaslona.
class SignatureResult {
  const SignatureResult({this.signatureBase64, required this.receivedByName});

  final String? signatureBase64;
  final String receivedByName;
}

/// Stranka se s prstom podpiše na telefon. To je dokazilo o vračilu.
///
/// Odpre se kot sheet nad zaslonom Vračilo, takoj ko so označeni vsi kosi
/// (QA v4 §6) — en prehod manj kot prej, ko je bil to ločen zaslon.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({
    super.key,
    required this.orderNumber,
    required this.itemCount,
    required this.defaultName,
  });

  static Future<SignatureResult?> show(
    BuildContext context, {
    required String orderNumber,
    required int itemCount,
    required String defaultName,
  }) {
    return showModalBottomSheet<SignatureResult>(
      context: context,
      isScrollControlled: true,
      // Poteza s prstom po podpisnem polju ne sme zapreti sheeta.
      enableDrag: false,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SignatureScreen(
        orderNumber: orderNumber,
        itemCount: itemCount,
        defaultName: defaultName,
      ),
    );
  }

  final String orderNumber;
  final int itemCount;
  final String defaultName;

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final _controller = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );
  late final _name = TextEditingController(text: widget.defaultName);
  bool _hasDrawn = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final drawn = _controller.isNotEmpty;
      if (drawn != _hasDrawn) setState(() => _hasDrawn = drawn);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _name.dispose();
    super.dispose();
  }

  String get _statement =>
      'Potrjujem prevzem ${widget.itemCount} ${_preprog(widget.itemCount)} '
      'iz naročila ${widget.orderNumber}.';

  static String _preprog(int n) {
    if (n == 1) return 'preproge';
    if (n == 2) return 'preprog';
    return 'preprog';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SizedBox(
        height: media.size.height * 0.88,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + media.padding.bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Podpis stranke',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Zapri',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  _statement,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Ime osebe, ki prevzema',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Podpis',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _controller.clear(),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Počisti'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _hasDrawn ? AppColors.primary : AppColors.border,
                      width: _hasDrawn ? 1.6 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.ready),
                onPressed: _hasDrawn ? _submit : null,
                icon: const Icon(Icons.check),
                label: const Text('Podpiši in zaključi'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Podpis se shrani skupaj z datumom, uro, seznamom kosov in '
                'imenom zaposlenega, ki je izvedel predajo.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final bytes = await _controller.toPngBytes();
    if (!mounted) return;
    Navigator.pop(
      context,
      SignatureResult(
        signatureBase64: bytes == null ? null : base64Encode(bytes),
        receivedByName: _name.text.trim(),
      ),
    );
  }
}
