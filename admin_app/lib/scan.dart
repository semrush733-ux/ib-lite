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
  final MobileScannerController _c = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  String? _hint;

  @override
  void dispose() {
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
          MobileScanner(controller: _c, onDetect: _found),
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
                _hint ?? 'Point the camera at the QR code on the client\'s TV.',
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
