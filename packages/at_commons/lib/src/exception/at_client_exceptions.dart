// ignore_for_file: use_super_parameters

import 'package:at_commons/src/exception/at_exceptions.dart';

class AtClientException extends AtException {
  /// The default constructor to preserve the backward compatibility.
  AtClientException(errorCode, message) : super(message);

  /// The named constructor that takes only message
  AtClientException.message(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtKeyException extends AtClientException {
  AtKeyException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtValueException extends AtClientException {
  AtValueException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtEncryptionException extends AtClientException {
  AtEncryptionException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtPublicKeyChangeException extends AtEncryptionException {
  AtPublicKeyChangeException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtPublicKeyNotFoundException extends AtEncryptionException {
  AtPublicKeyNotFoundException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class AtDecryptionException extends AtClientException {
  AtDecryptionException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super.message(message,
            intent: intent, exceptionScenario: exceptionScenario);
}

class AtPrivateKeyNotFoundException extends AtDecryptionException {
  AtPrivateKeyNotFoundException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class SharedKeyNotFoundException extends AtDecryptionException {
  SharedKeyNotFoundException(message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

class SelfKeyNotFoundException extends AtDecryptionException {
  SelfKeyNotFoundException(message,
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
  InvalidPinException(errorCode, message) : super(errorCode, message);

  InvalidPinException.message(String message) : super.message(message);
}
