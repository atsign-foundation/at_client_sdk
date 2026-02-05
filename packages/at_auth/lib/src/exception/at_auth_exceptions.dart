import 'package:at_commons/at_commons.dart';

class AtAuthenticationException extends AtException {
  AtAuthenticationException(super.message);
}

class AtKeysFileExistsException extends AtException {
  AtKeysFileExistsException(super.message,
      {super.intent, super.exceptionScenario});
}
