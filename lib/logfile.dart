import 'dart:io';

/// Test builds: appends one log line to [path] (see kLogFile). Never throws.
void writeLogLine(String path, String line) {
  try {
    File(path).writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}
