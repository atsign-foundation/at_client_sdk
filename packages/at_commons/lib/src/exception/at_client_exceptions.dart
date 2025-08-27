// ignore_for_file: use_super_parameters

import 'package:at_commons/src/exception/at_exceptions.dart';

class AtClientException extends AtException {
  /// The default constructor to preserve the backward compatibility.
  AtClientException(dynamic errorCode, String message) : super(message);

  /// The named constructor that takes only message
  AtClientException.message(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtKeyException extends AtClientException {
  AtKeyException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtValueException extends AtClientException {
  AtValueException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtEncryptionException extends AtClientException {
  AtEncryptionException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtPublicKeyChangeException extends AtEncryptionException {
  AtPublicKeyChangeException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtPublicKeyNotFoundException extends AtEncryptionException {
  AtPublicKeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtDecryptionException extends AtClientException {
  AtDecryptionException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtPrivateKeyNotFoundException extends AtDecryptionException {
  AtPrivateKeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class SharedKeyNotFoundException extends AtDecryptionException {
  SharedKeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class SelfKeyNotFoundException extends AtDecryptionException {
  SelfKeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtKeyNotFoundException extends AtClientException {
  AtKeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class InvalidPinException extends AtClientException {
  InvalidPinException(dynamic errorCode, message) : super(errorCode, message);

  InvalidPinException.message(String message) : super.message(message);
}
