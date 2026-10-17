import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'backend.dart';
import 'config.dart';
import 'i18n.dart';
import 'logbook.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

/// "Report a problem": what went wrong (a quick choice and an optional note) goes to the website
/// with the app's recent log, this TV's model and the last stream it played. The admin reads it
/// in the Admin Panel app (More › Problem reports) or in WordPress (Lite Player › Problem reports).
/// No login, password or full stream address is sent (see LogBook).

const _reasons = [
  'A channel does not play',
  'Picture freezes or buffers',
  'No sound or wrong language',
  'A film or series does not play',
  'TV Guide is wrong or missing',
  'The app is slow or closes',
  'Something else',
];

/// Last report sent from this TV (a second one only after a short wait).
DateTime? _lastSent;

Future<void> showReportDialog(BuildContext context) async {
  log('report dialog');
  await showDialog<void>(context: context, builder: (_) => const _ReportDialog());
}

/// The TV's model, Android version, memory and screen, for the report.
Future<Map<String, Object>> _deviceInfo() async {
  final out = <String, Object>{};
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final m = await const MethodChannel('b1g/device').invokeMethod<Map<dynamic, dynamic>>('deviceInfo');
      m?.forEach((k, v) {
        if (v != null && '$v'.isNotEmpty) out['$k'] = v is bool || v is num ? v : '$v';
      });
    } catch (e) {
      log('device info failed: ${e.runtimeType}');
    }
  }
  if (out.isEmpty) out['system'] = kIsWeb ? 'web' : defaultTargetPlatform.name;
  return out;
}

String _platform() {
  if (kTizen) return kTvPlatform;
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.android ? 'android-tv' : defaultTargetPlatform.name;
}

String _hostOf(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.host.isEmpty) return '';
  return u.hasPort ? '${u.host}:${u.port}' : u.host;
}

/// Sends the report. Returns the website's report number (0 when it gave none).
Future<int> sendProblemReport({required String reason, required String note}) async {
  final device = await _deviceInfo();
  final stream = LastStream.toMap();
  final server = _hostOf(Store.isM3u ? Store.m3uUrl : Store.server);
  log('report send reason="$reason" note=${note.length} stream=${stream['state'] ?? 'none'}');
  final answer = await Backend.sendReport({
    'reason': reason,
    'note': note,
    'app_version': '${Backend.appVersionName.isEmpty ? '?' : Backend.appVersionName} (${Backend.appVersionCode})',
    'platform': _platform(),
    'device': device,
    'stream': stream,
    'playlist': Store.playlistName,
    'server': server,
    'language': currentLanguage,
    'profile': Store.kidsMode ? '${Store.profileId} (kids)' : Store.profileId,
    'log': LogBook.text(),
  });
  _lastSent = DateTime.now();
  return int.tryParse('${answer['report_id'] ?? 0}') ?? 0;
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();
  int? _reason;
  bool _sending = false;
  String _error = '';
  int? _sentNumber;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final last = _lastSent;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 60)) {
      setState(() => _error = t('A report was sent a moment ago. Please wait a minute.'));
      return;
    }
    if (_reason == null && _note.text.trim().isEmpty) {
      setState(() => _error = t('Choose what went wrong (or write a note).'));
      return;
    }
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final number = await sendProblemReport(
        reason: _reason == null ? '' : _reasons[_reason!],
        note: _note.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentNumber = number;
      });
    } catch (e) {
      log('report failed: ${e.runtimeType}');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e is BackendException ? e.message : t('Could not send the report. Check the internet and try again.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sentNumber;
    if (sent != null) {
      return AlertDialog(
        backgroundColor: C.panel,
        title: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF2ECC71)),
            const SizedBox(width: 10),
            Expanded(child: Text(t('Report sent'))),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: Text(
            sent > 0
                ? '${t('Thank you. Your report number is')} $sent.\n${t('The support team can see what happened on this TV.')}'
                : '${t('Thank you.')}\n${t('The support team can see what happened on this TV.')}',
            style: const TextStyle(height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: C.accent)),
          ),
        ],
      );
    }
    return AlertDialog(
      backgroundColor: C.panel,
      title: Row(
        children: [
          const Icon(Icons.report_problem_rounded, color: C.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(t('Report a problem'))),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t('What went wrong? The app sends its recent log, this TV\'s model and the last channel or film to the support team. No password is sent.'),
                style: const TextStyle(fontSize: 13.5, color: C.dim, height: 1.45),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _reasons.length; i++)
                    TvFocus(
                      autofocus: i == 0,
                      selected: _reason == i,
                      radius: 18,
                      color: C.card,
                      onTap: () => setState(() {
                        _reason = i;
                        _error = '';
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_reason == i) ...[
                              const Icon(Icons.check_rounded, size: 16, color: C.accent),
                              const SizedBox(width: 6),
                            ],
                            Text(t(_reasons[i]),
                                style: TextStyle(
                                    fontSize: 13.5, fontWeight: _reason == i ? FontWeight.w800 : FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              TvField(
                controller: _note,
                label: t('Note (optional), e.g. the channel name'),
                icon: Icons.edit_note_rounded,
                action: TextInputAction.done,
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(_error, style: const TextStyle(color: C.danger, fontSize: 13.5)),
              ],
              if (Backend.deviceId.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('MAC Address: ${Backend.deviceId}', style: const TextStyle(fontSize: 12.5, color: C.dim)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(t('Cancel')),
        ),
        TextButton(
          onPressed: _sending ? null : _send,
          child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: C.accent))
              : Text(t('Send'), style: const TextStyle(color: C.accent, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
