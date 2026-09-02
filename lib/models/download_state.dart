import 'package:http/http.dart' as http;

/// Tracks real-time download state for a single model.
class DownloadState {
  final String filename;
  double totalBytes;
  double receivedBytes;
  double speedBytesPerSec;
  DateTime startedAt;
  bool isActive;
  bool isCancelled;

  /// True while the finished file is being hashed for verification.
  bool isVerifying = false;

  /// The HTTP client for this transfer, so cancelling one download does not
  /// tear down the connections of any others.
  http.Client? client;

  DownloadState({
    required this.filename,
    required this.totalBytes,
    this.receivedBytes = 0,
    this.speedBytesPerSec = 0,
    DateTime? startedAt,
    this.isActive = true,
    this.isCancelled = false,
  }) : startedAt = startedAt ?? DateTime.now();

  double get progress => totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
  double get percent => progress * 100;

  String get downloadedStr => _formatBytes(receivedBytes);
  String get totalStr => _formatBytes(totalBytes);
  String get remainingStr => _formatBytes(totalBytes - receivedBytes);
  String get speedStr => '${_formatBytes(speedBytesPerSec)}/s';

  Duration get eta {
    if (speedBytesPerSec <= 0) return Duration.zero;
    final remaining = totalBytes - receivedBytes;
    return Duration(seconds: (remaining / speedBytesPerSec).ceil());
  }

  String get etaStr {
    final d = eta;
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inSeconds}s';
  }

  static String _formatBytes(double bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '${bytes.toStringAsFixed(0)} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
