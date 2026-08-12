/// When implemented on a given class, other code can subscribe to
/// [ProgressEvent]s and choose how to provide feedback to users - e.g. by
/// logging to stderr or stdout in a CLI program, or adding to a UI widget in
/// a Flutter app, etc
abstract interface class ProgressPublisher {
  Stream<ProgressEvent> subscribeProgress();
}

/// The events which are published by a [ProgressPublisher]
class ProgressEvent {
  final DateTime time = DateTime.now();
  final String group;
  final String msg;
  final ProgressEventType type;

  ProgressEvent({
    required this.group,
    required this.msg,
    required this.type,
  });

  /// Plain text, deliberately uncoloured.
  ///
  /// A [ProgressEvent] is a model, and a model has no business deciding how it
  /// is rendered — the ANSI escapes this used to embed showed up as literal
  /// `[34m` noise in log files, Flutter widgets and browser consoles. Colour is
  /// the renderer's job: CLIs import `package:at_utils/at_utils_cli.dart` and
  /// apply `ProgressEventType.chalkFn` themselves.
  @override
  String toString() => '${time.toIso8601String()}'
      ' | $type | $group'
      ' | $msg';
}

/// The type of [ProgressEvent]
enum ProgressEventType { info, success, warning, error }
