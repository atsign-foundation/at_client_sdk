import 'package:chalkdart/chalk.dart';

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

  @override
  String toString() => '${time.toIso8601String()}'
      ' | ${type.chalkFn('$type | $group')}'
      ' | $msg';
}

/// The type of [ProgressEvent]
enum ProgressEventType { info, success, warning, error }

/// A useful extension to assist in colour-coding output based on the
/// [ProgressEventType]
extension ChalkFunction on ProgressEventType {
  Function get chalkFn {
    switch (this) {
      case ProgressEventType.info:
        return chalk.blue;
      case ProgressEventType.success:
        return chalk.green;
      case ProgressEventType.warning:
        return chalk.orange;
      case ProgressEventType.error:
        return chalk.red;
    }
  }
}
