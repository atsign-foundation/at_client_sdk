import 'dart:async';

import 'package:at_utils/at_progress.dart';

/// The single progress stream an enrollment reports on, shared by the
/// collaborators that make up the implementation.
///
/// Submission and the approval handshake both report progress and a caller
/// listens once, so the stream has to outlive whichever of them is running:
/// it is owned here rather than by either.
class EnrollmentProgress {
  final StreamController<ProgressEvent> _controller =
      StreamController<ProgressEvent>.broadcast();

  Stream<ProgressEvent> get stream => _controller.stream;

  void add(String group, String message, ProgressEventType progressEventType) {
    var progressEvent =
        ProgressEvent(group: group, msg: message, type: progressEventType);
    _controller.add(progressEvent);
  }
}
