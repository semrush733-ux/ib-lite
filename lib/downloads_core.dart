/// One downloaded (or downloading) film / episode. Shared by the Android downloader and the
/// web stub, so screens can use it everywhere.
class DlItem {
  DlItem({
    required this.id,
    required this.title,
    required this.url,
    required this.ext,
    this.subtitle = '',
    this.cover = '',
    this.path = '',
    this.total = 0,
    this.got = 0,
    this.state = DlState.queued,
    this.error = '',
    int? added,
  }) : added = added ?? DateTime.now().millisecondsSinceEpoch;

  final String id; // e.g. "vod:12345"
  final String title;
  final String subtitle;
  final String cover;
  final String url;
  final String ext;
  String path;
  int total; // bytes, 0 = not known yet
  int got;
  DlState state;
  String error;
  final int added;

  /// Bytes a second right now (not saved).
  int speed = 0;

  double get fraction => total > 0 ? (got / total).clamp(0.0, 1.0) : 0.0;
  int get percent => (fraction * 100).floor().clamp(0, 100);
  bool get done => state == DlState.done;

  /// Seconds left at the current speed (0 = unknown).
  int get secondsLeft => speed > 0 && total > got ? ((total - got) / speed).ceil() : 0;

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'cover': cover,
        'url': url,
        'ext': ext,
        'path': path,
        'total': total,
        'got': got,
        'state': state.name,
        'error': error,
        'added': added,
      };

  static DlItem fromJson(Map<String, dynamic> j) => DlItem(
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        cover: '${j['cover'] ?? ''}',
        url: '${j['url'] ?? ''}',
        ext: '${j['ext'] ?? 'mp4'}',
        path: '${j['path'] ?? ''}',
        total: (j['total'] as num?)?.toInt() ?? 0,
        got: (j['got'] as num?)?.toInt() ?? 0,
        state: DlState.values.firstWhere((s) => s.name == j['state'], orElse: () => DlState.paused),
        error: '${j['error'] ?? ''}',
        added: (j['added'] as num?)?.toInt(),
      );
}

enum DlState {
  queued, // waiting for its turn
  running, // downloading now
  waiting, // held back while a video plays (one connection per account)
  paused, // paused by the viewer
  failed,
  done,
}

String fmtBytes(num b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(1)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '${b.toInt()} B';
}

String fmtSpeed(int bps) {
  if (bps >= 1 << 20) return '${(bps / (1 << 20)).toStringAsFixed(1)} MB/s';
  return '${(bps / (1 << 10)).toStringAsFixed(0)} KB/s';
}

String fmtLeft(int s) {
  if (s <= 0) return '';
  if (s < 60) return '${s}s left';
  if (s < 3600) return '${(s / 60).ceil()} min left';
  return '${s ~/ 3600}h ${((s % 3600) / 60).round()}m left';
}
