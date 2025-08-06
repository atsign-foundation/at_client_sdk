import 'package:at_commons/at_commons.dart';

/// AtExceptionManager is responsible for creating instances of the appropriate exception
/// classes for a given exception scenario.
class AtExceptionManager {
  /// This method is specific to client side exception handling.
  /// Returns [AtClientException] or sub-class of [AtClientException]
  static AtClientException createException(AtException atException) {
    // If the instance of atException is AtClientException. return as is.
    if (atException is AtClientException) {
      return atException;
    }
    // The KeyNotFoundException is a not a sub-class of AtClientException.
    // Hence if the exception is triggered from the client side
    // convert it to AtKeyNotFoundException and return it.
    if (atException is KeyNotFoundException) {
      return AtKeyNotFoundException(atException.message,
          intent: atException.intent,
          exceptionScenario: atException.exceptionScenario)
        ..fromException(atException);
    }
    // Else wrap the atException into AtClientException and return.
    return (AtClientException.message(atException.message,
        intent: atException.intent,
        exceptionScenario: atException.exceptionScenario))
      ..fromException(atException);
  }
}
