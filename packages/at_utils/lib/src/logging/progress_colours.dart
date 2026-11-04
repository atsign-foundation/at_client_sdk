// ignore_for_file: implicit_call_tearoffs

import 'package:at_utils/src/logging/progress.dart';
import 'package:chalkdart/chalk.dart';

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
