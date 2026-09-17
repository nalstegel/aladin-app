import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/scan.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/enums.dart';
import '../rugs/rug_detail_screen.dart';
import '../widgets/common.dart';
import 'scan_capture_screen.dart';
import 'work_list_screen.dart';

/// Zavihek Skeniraj: živa kamera in bližnjice do delovnih seznamov.
///
/// Hitri način je namenjen delu ob stroju — skeniraš kos za kosom in vsak se
/// premakne za korak naprej, brez odpiranja zaslonov.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key, this.active = true});

  /// Kamera teče samo, kadar je zavihek res izbran. Brez tega bi tekla ves
  /// čas, ko je aplikacija odprta, in praznila baterijo.
  final bool active;

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

/// Bližnjice pod okvirjem — koraki, ki jih delavec dejansko dela ob stroju.
/// "Mere in cena" (finishing) je namenoma zunaj: do njega se pride prek
/// filtra v Naročilih in prek ploščice na Danes.
const _shortcuts = [
  RugStatus.awaitingPickup,
  RugStatus.awaitingWash,
  RugStatus.drying,
  RugStatus.ready,
  RugStatus.returned,
];

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  MobileScannerController? _controller;
  bool _quickMode = false;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  String? _flash;
  Color _flashColor = AppColors.ready;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(ScannerScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _stop();
  }

  @override
  void dispose() {
    // Namenoma brez _stop(): ta kliče setState, kar med dispose vrže napako.
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  void _start() {
    if (_controller != null) return;
    setState(() {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        formats: const [BarcodeFormat.qrCode],
      );
    });
  }

  void _stop() {
    if (_controller == null) return;
    _controller!.dispose();
    setState(() => _controller = null);
  }

  void _onDetect(BarcodeCapture capture) {
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;
    final code = normalizeScanCode(raw);
    if (code.isEmpty) return;

    // Kamera isto kodo prebere večkrat na sekundo.
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inSeconds < 3) return;
    _lastCode = code;
    _lastAt = now;

    _handle(code);
  }

  void _handle(String code) {
    final state = ref.read(repositoryProvider);
    final item = state.item(code);

    if (item == null) {
      _showFlash('Kos $code ni v sistemu', AppColors.danger);
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

  /// Ročni vnos je zasilni izhod, kadar je etiketa strgana ali umazana.
  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ročni vnos kode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vpiši oznako s etikete, npr. LJ-001-2.',
              style: TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.visiblePassword,
              decoration: const InputDecoration(hintText: 'LJ-001-2'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Odpri'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (code == null) return;
    final normalized = normalizeScanCode(code);
    if (normalized.isEmpty) return;
    if (!mounted) return;
    _handle(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final counts = ref.watch(productionCountsProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            const Center(
              child: Text(
                'Skeniraj',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.text,
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Skeniraj kodo na etiketi preproge',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 18),
            _viewfinder(),
            const SizedBox(height: 14),
            _quickModeToggle(),
            const SizedBox(height: 14),
            MenuGroup(
              rows: [
                for (final s in _shortcuts)
                  MenuRow(
                    icon: AppIcons.forRug(s),
                    iconColor: AppColors.forRug(s),
                    label: s.label,
                    trailing: _count(counts[s] ?? 0, AppColors.forRug(s)),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkListScreen(status: s),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _manualEntry,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Ročni vnos kode'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _count(int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$n',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      );

  Widget _viewfinder() {
    return AspectRatio(
      aspectRatio: 1.15,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null)
                MobileScanner(controller: _controller!, onDetect: _onDetect)
              else
                const ColoredBox(color: AppColors.surface),
              const ScanFrameOverlay(color: Colors.white),
              if (_flash != null)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _flashColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _flash!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    _camAction(Icons.flashlight_on_outlined,
                        () => _controller?.toggleTorch()),
                    const SizedBox(width: 8),
                    _camAction(Icons.cameraswitch_outlined,
                        () => _controller?.switchCamera()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _camAction(IconData icon, VoidCallback onTap) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      );

  Widget _quickModeToggle() {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Row(
        children: [
          Icon(
            _quickMode ? Icons.bolt : Icons.bolt_outlined,
            size: 20,
            color: _quickMode ? AppColors.primary : AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Hitri način',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  _quickMode
                      ? 'Vsak skeniran kos gre korak naprej.'
                      : 'Skeniranje odpre podrobnosti kosa.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _quickMode,
            onChanged: (v) => setState(() => _quickMode = v),
          ),
        ],
      ),
    );
  }
}
