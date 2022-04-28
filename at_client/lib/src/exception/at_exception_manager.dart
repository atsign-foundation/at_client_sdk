import 'package:at_client/src/exception/error_message.dart';
import 'package:at_commons/at_commons.dart';

class AtExceptionManager {
  static final AtExceptionManager _singleton = AtExceptionManager._internal();

  AtExceptionManager._internal();

  factory AtExceptionManager.getInstance() {
    return _singleton;
  }

  AtException createException(Intent intent, AtException atException) {
    atException.message =
        '${IntentMessage.getMessage(intent)} : ${atException.message}';
    atException.format();
    return atException;
  }
}
