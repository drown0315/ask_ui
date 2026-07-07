import '../sessions/session_store.dart';

class SnapshotCaptureRequest {
  const SnapshotCaptureRequest({
    required this.session,
    required this.commentId,
    required this.maxSizeBytes,
  });

  final BridgeSession session;
  final String commentId;
  final int maxSizeBytes;
}

class SnapshotCaptureResult {
  const SnapshotCaptureResult.available({
    required this.path,
    required this.mimeType,
    required this.sizeBytes,
  }) : isAvailable = true;

  const SnapshotCaptureResult.unavailable()
      : isAvailable = false,
        path = '',
        mimeType = '',
        sizeBytes = 0;

  final bool isAvailable;
  final String path;
  final String mimeType;
  final int sizeBytes;
}

abstract interface class SnapshotCapture {
  Future<SnapshotCaptureResult> capture(SnapshotCaptureRequest request);
}

class UnavailableSnapshotCapture implements SnapshotCapture {
  const UnavailableSnapshotCapture();

  @override
  Future<SnapshotCaptureResult> capture(SnapshotCaptureRequest request) async {
    return const SnapshotCaptureResult.unavailable();
  }
}
