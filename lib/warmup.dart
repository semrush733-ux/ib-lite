/// Gets the way to an IPTV server ready before a stream is asked for: name lookup (DNS) and a
/// first connection, so the real stream skips that part. Only touches the server's address,
/// never opens a stream (most accounts allow one stream at a time).
export 'warmup_web.dart' if (dart.library.io) 'warmup_io.dart';
