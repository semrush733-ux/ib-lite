import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api.dart';

/// Camera scanner for the QR code on the client's TV. Pops with (MAC Address, Device Key).
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  // Full HD frames: a QR code on a TV across the room still has enough pixels.
  final MobileScannerController _c = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    cameraResolution: const Size(1920, 1080),
  );
  bool _done = false;
  String? _hint;

  // Auto zoom: while nothing is found, the camera steps in closer and back out, so a TV far
  // away comes into reading size by itself. Pinch or the slider takes over by hand.
  static const _steps = [0.0, 0.2, 0.35, 0.5, 0.65, 0.8, 0.5, 0.25];
  int _step = 0;
  double _zoom = 0;
  double _pinchStart = 0;
  bool _manual = false;
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    _auto = Timer.periodic(const Duration(milliseconds: 1700), (_) {
      if (_done || _manual || !mounted) return;
      _step = (_step + 1) % _steps.length;
      _setZoom(_steps[_step]);
    });
  }

  Future<void> _setZoom(double z) async {
    z = z.clamp(0.0, 1.0);
    if (mounted) setState(() => _zoom = z);
    try {
      await _c.setZoomScale(z);
    } catch (_) {}
  }

  @override
  void dispose() {
    _auto?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _found(BarcodeCapture cap) {
    if (_done) return;
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v == null) continue;
      final r = parseQr(v);
      if (r != null) {
        _done = true;
        Navigator.of(context).pop(r);
        return;
      }
      setState(() => _hint = 'This QR code is not from the TV app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size.width * 0.7;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan the TV QR code'),
        actions: [
          IconButton(icon: const Icon(Icons.flash_on_rounded), onPressed: () => _c.toggleTorch()),
          IconButton(icon: const Icon(Icons.cameraswitch_rounded), onPressed: () => _c.switchCamera()),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onScaleStart: (_) => _pinchStart = _zoom,
            onScaleUpdate: (d) {
              if (d.pointerCount < 2) return;
              _manual = true;
              _setZoom(_pinchStart + (d.scale - 1) * 0.5);
            },
            child: MobileScanner(controller: _c, onDetect: _found),
          ),
          Positioned(
            top: 16,
            left: 24,
            right: 24,
            child: Row(
              children: [
                const Icon(Icons.zoom_out, color: Colors.white70),
                Expanded(
                  child: Slider(
                    value: _zoom,
                    activeColor: const Color(0xFFE3262F),
                    onChanged: (v) {
                      _manual = true;
                      _setZoom(v);
                    },
                  ),
                ),
                const Icon(Icons.zoom_in, color: Colors.white70),
                TextButton(
                  onPressed: () => setState(() => _manual = !_manual),
                  child: Text(_manual ? 'AUTO' : 'AUTO ✓',
                      style: TextStyle(color: _manual ? Colors.white70 : const Color(0xFFE3262F), fontWeight: FontWeight.w800)),
                ),
              ],
            ),
          ),
          IgnorePointer(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE3262F), width: 4),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(14)),
              child: Text(
                _hint ?? 'Point the camera at the QR code on the TV. Far away? It zooms in by itself, or pinch to zoom.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A screenshot or photo of the TV's QR code (e.g. sent by the client on WhatsApp).
Future<(String, String)?> scanFromPicture(BuildContext context) async {
  final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (picked == null) return null;
  final c = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  try {
    final cap = await c.analyzeImage(picked.path);
    for (final b in cap?.barcodes ?? const <Barcode>[]) {
      final v = b.rawValue;
      if (v == null) continue;
      final r = parseQr(v);
      if (r != null) return r;
    }
  } catch (_) {
  } finally {
    c.dispose();
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No TV QR code found in this picture. Try a clearer screenshot.')),
    );
  }
  return null;
}
