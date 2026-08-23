import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../rugs/rug_detail_screen.dart';

/// Skeniranje QR etikete. Vsaka koda vodi na točno določen kos.
///
/// Hitri način je namenjen delu ob stroju: skeniraš kos za kosom in vsak
/// se premakne za korak naprej, brez odpiranja zaslonov.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key, this.onResult, this.title});

  /// Če je podan, skener vrne prebrani ID namesto odpiranja podrobnosti.
  /// Uporablja ga postopek vračila.
  final void Function(String itemId)? onResult;
  final String? title;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _quickMode = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _flash;
  Color _flashColor = AppColors.ready;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Sprejmemo golo oznako ("1847-2") ali povezavo ("aladin://rug/1847-2").
  String _normalize(String raw) {
    final trimmed = raw.trim();
    final slash = trimmed.lastIndexOf('/');
    final code = slash >= 0 ? trimmed.substring(slash + 1) : trimmed;
    return code.toUpperCase().replaceAll(RegExp(r'[^0-9\-]'), '');
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final code = _normalize(raw);
    if (code.isEmpty) return;

    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inSeconds < 3) return;
    _lastCode = code;
    _lastAt = now;

    final state = ref.read(repositoryProvider);
    final item = state.item(code);

    if (item == null) {
      _showFlash('Kos $code ni v sistemu', AppColors.danger);
      return;
    }

    if (widget.onResult != null) {
      widget.onResult!(item.id);
      return;
    }

    if (!_quickMode) {
      _open(item.id);
      return;
    }

    final repo = ref.read(repositoryProvider.notifier);
    final next = repo.nextStatusFor(item);
    if (next == null) {
      // Naslednji korak zahteva vnos — odpremo podrobnosti kosa.
      _open(item.id);
      return;
    }
    repo.advance(item.id);
    _showFlash('${item.id} → ${next.label}', AppColors.forRug(next));
  }

  void _open(String id) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RugDetailScreen(itemId: id)),
    );
  }

  void _showFlash(String message, Color color) {
    setState(() {
      _flash = message;
      _flashColor = color;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title ?? 'Skeniraj etiketo'),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          _frame(),
          if (_flash != null)
            Positioned(
              left: 16,
              right: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _flashColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _flash!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.onResult == null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          _modeButton('Odpri kos', !_quickMode,
                              () => setState(() => _quickMode = false)),
                          _modeButton('Hitri način', _quickMode,
                              () => setState(() => _quickMode = true)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _quickMode
                          ? 'Vsak skeniran kos gre samodejno korak naprej.'
                          : 'Skeniranje odpre podrobnosti preproge.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _modeButton(String label, bool selected, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame() {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 3),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}
