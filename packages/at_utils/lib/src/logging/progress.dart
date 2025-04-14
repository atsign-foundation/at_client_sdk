import 'package:chalkdart/chalk.dart';

enum ProgressEventType {
  info,
  success,
  warning,
  failure
}

extension ChalkFunction on ProgressEventType {
  Function get chalkFn {
    switch (this) {
      case ProgressEventType.info:
        return chalk.blue;
      case ProgressEventType.success:
        return chalk.green;
      case ProgressEventType.warning:
        return chalk.orange;
      case ProgressEventType.failure:
        return chalk.red;
    }
  }
}

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

abstract interface class ProgressPublisher {
  Stream<ProgressEvent> subscribeProgress();
  addProgress(ProgressEvent pe);
}
