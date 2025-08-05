import 'dart:collection';

import 'package:at_commons/src/exception/at_exceptions.dart';

/// Class to maintain stack of exceptions to form a chained exception.
class AtExceptionStack implements Comparable<AtChainedException> {
  final _exceptionList = Queue<AtChainedException>();

  void add(AtChainedException atChainedException) {
    if (compareTo(atChainedException) == 0) {
      return;
    }
    _exceptionList.addFirst(atChainedException);
  }

  /// Concatenate the error messages in the exceptionList and returns a trace message
  String getTraceMessage() {
    var size = _exceptionList.length;
    String fullMessage = '';
    if (size > 0) {
      fullMessage =
          '${getIntentMessage(_exceptionList.first.intent)} caused by\n';
    }
    for (AtChainedException element in _exceptionList) {
      size--;
      fullMessage += element.message;
      if (size != 0) {
        fullMessage += ' caused by\n';
      }
    }
    return fullMessage;
  }

  /// Accepts the Intent and returns a message
  String getIntentMessage(Intent intent) {
    return 'Failed to ${intent.name}';
  }

  @override
  int compareTo(AtChainedException atChainedException) {
    for (var element in _exceptionList) {
      if (element.message == atChainedException.message) {
        return 0;
      }
    }
    return 1;
  }
}

class AtChainedException {
  late Intent intent;
  late ExceptionScenario exceptionScenario;
  late String message;

  AtChainedException(this.intent, this.exceptionScenario, this.message);
}
