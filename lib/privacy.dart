import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart' show kSiteBase;
import 'config.dart';
import 'theme.dart';
import 'widgets.dart';

/// The website's privacy policy. Google Play wants it reachable inside the app as well as on the
/// store listing: Settings › Application Info and the first screen open [showPrivacyDialog].
String get kPrivacyUrl => kPrivacyUrlBuild.isNotEmpty ? kPrivacyUrlBuild : '$kSiteBase/privacy-policy-2/';

/// What the app sends and why (the same as the website's policy), a QR code to the full policy
/// for a phone, and "Open" for devices with a browser.
Future<void> showPrivacyDialog(BuildContext context) {
  log('screen=privacy');
  final url = kPrivacyUrl;
  var note = '';
  return showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => Dialog(
      backgroundColor: C.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 22, 26, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(Icons.shield_rounded, color: C.accent, size: 26),
                  SizedBox(width: 10),
                  Text('Privacy Policy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 14),
              Flexible(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: SingleChildScrollView(
                        child: Text(_summary, style: TextStyle(fontSize: 13.5, height: 1.45)),
                      ),
                    ),
                    const SizedBox(width: 22),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: QrImageView(
                            data: url,
                            version: QrVersions.auto,
                            size: 150,
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: 170,
                          child: Text('Scan for the full policy\n${url.replaceFirst(RegExp(r'^https?://'), '')}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: C.dim, height: 1.35)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (note.isNotEmpty)
                    Expanded(child: Text(note, style: const TextStyle(fontSize: 13, color: C.accent))),
                  TvFocus(
                    radius: 10,
                    color: C.card,
                    onTap: () async {
                      var ok = false;
                      try {
                        ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                      } catch (_) {}
                      if (!ok && ctx.mounted) {
                        setState(() => note = 'No web browser on this device: scan the QR code with your phone.');
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      child: Text('Open full policy', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TvFocus(
                    autofocus: true,
                    radius: 10,
                    color: C.accent,
                    focusBorder: Colors.white,
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                      child: Text('Close',
                          style: TextStyle(color: C.onAccent, fontSize: 14.5, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    )),
  );
}

const _summary = 'This app is a media player only: it contains no channels, films or other content and sells none.\n\n'
    'What the app sends to our website, and why:\n'
    '•  Device identifiers (the MAC address where Android gives it, the Android ID) and the device model, '
    'to link this device to the playlists you add on the website and to manage its trial or licence.\n'
    '•  The app version and the IP address of each request, for security and to solve problems. The city for '
    'the weather on the home screen is worked out from the IP address; the app does not use GPS.\n'
    '•  Problem reports, only when you send one: the app\'s recent log and this device\'s details (no passwords).\n\n'
    'Playlists you add on the website are kept there (passwords encrypted) and are only used to deliver them to '
    'this device. Settings, favourites and history stay on this device. Film details come from TMDB.\n\n'
    'We do not sell personal data, show ads or record what you watch. You can ask us at any time to delete all '
    'data of this device: the contact address is in the full policy.';

/// A small "Privacy Policy" button (first screen, Settings › Application Info).
class PrivacyButton extends StatelessWidget {
  const PrivacyButton({super.key, this.color = C.card});

  final Color color;

  @override
  Widget build(BuildContext context) => TvFocus(
        radius: 18,
        color: color,
        onTap: () => showPrivacyDialog(context),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_rounded, size: 17, color: C.dim),
              SizedBox(width: 8),
              Text('Privacy Policy', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
}
