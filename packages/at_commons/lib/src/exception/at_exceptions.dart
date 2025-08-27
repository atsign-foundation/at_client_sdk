// ignore_for_file: use_super_parameters

import 'package:at_commons/at_commons.dart';

/// The class [AtException] and its subclasses represents various exceptions that can arise
/// while using the @ protocol.
class AtException implements Exception {
  /// Represents error message that details the cause of the exception
  String message;

  Intent? intent;

  ExceptionScenario? exceptionScenario;

  AtExceptionStack _traceStack = AtExceptionStack();

  AtException(this.message, {this.intent, this.exceptionScenario}) {
    if (intent != null && exceptionScenario != null) {
      _traceStack.add(AtChainedException(intent!, exceptionScenario!, message));
    }
  }

  AtException fromException(AtException atException) {
    _traceStack = atException._traceStack;
    return atException;
  }

  @override
  String toString() {
    return 'Exception: $message';
  }

  void stack(AtChainedException atChainedException) {
    _traceStack.add(atChainedException);
  }

  String getTraceMessage() {
    return _traceStack.getTraceMessage();
  }
}

/// The class [AtConnectException] and its subclasses represent any issues that prevents an connection to the root or the secondary server
class AtConnectException extends AtException {
  AtConnectException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

/// Exception thrown when there is an issue connecting to root server
class RootServerConnectivityException extends AtConnectException {
  RootServerConnectivityException(String message) : super(message);
}

/// Exception thrown when there is an issue connecting to secondary server
class SecondaryServerConnectivityException extends AtConnectException {
  SecondaryServerConnectivityException(String message) : super(message);
}

/// Exception thrown when a client tries to execute a verb or establish a connection but doesn't have the required permissions
class UnAuthorizedException extends AtConnectException {
  UnAuthorizedException(String message) : super(message);
}

/// Exception thrown when the requested atsign's secondary url is not present in Root server
class SecondaryNotFoundException extends AtConnectException {
  SecondaryNotFoundException(String message) : super(message);
}

/// Exception thrown when from-pol handshake fails between two secondary servers
class HandShakeException extends AtConnectException {
  HandShakeException(String message) : super(message);
}

/// Thrown when trying to perform a verb execution which requires authentication
class UnAuthenticatedException extends AtConnectException {
  UnAuthenticatedException(String message) : super(message);
}

/// Thrown when trying to perform a read/write on a connection which is invalid
class ConnectionInvalidException extends AtConnectException {
  ConnectionInvalidException(String message) : super(message);
}

/// Thrown when trying to perform a read/write on an outbound connection which is invalid
class OutBoundConnectionInvalidException extends AtConnectException {
  OutBoundConnectionInvalidException(String message) : super(message);
}

/// Exception thrown when security certification validation on root or secondary server fails
class AtCertificateValidationException extends AtException {
  AtCertificateValidationException(String message) : super(message);
}

/// Exception thrown when there is any issue related to socket operations e.g read/write
class AtIOException extends AtException {
  AtIOException(String message) : super(message);
}

/// Exception thrown when an @ protocol verb has an invalid syntax.
class InvalidSyntaxException extends AtException {
  InvalidSyntaxException(String message) : super(message);
}

/// Exception thrown when a verb fails due to some state being not as expected
class IllegalStateException extends AtException {
  IllegalStateException(String message) : super(message);
}

/// Exception thrown when an atsign name provided is invalid.
class InvalidAtSignException extends AtException {
  InvalidAtSignException(String message) : super(message);
}

/// Exception thrown when data size passed to the socket is greater than configured buffer size
class BufferOverFlowException extends AtException {
  BufferOverFlowException(String message) : super(message);
}

/// Exception thrown when an atsign's secondary url cannot be reached or is unavailable
/// Should this be extending AtConnectException?
class SecondaryConnectException extends AtException {
  SecondaryConnectException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

/// Exception thrown when [AtKey.key] is not present in the keystore
class KeyNotFoundException extends AtException {
  KeyNotFoundException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

/// Exception thrown when any parameter in a verb command is invalid
class IllegalArgumentException extends AtException {
  IllegalArgumentException(String message) : super(message);
}

/// Exception thrown when no response is received before the timeout duration
class AtTimeoutException extends AtException {
  AtTimeoutException(String message,
      {Intent? intent, ExceptionScenario? exceptionScenario})
      : super(message, intent: intent, exceptionScenario: exceptionScenario);
}

/// Exception thrown when request to secondary server is invalid
class InvalidRequestException extends AtException {
  InvalidRequestException(String message) : super(message);
}

/// Exception thrown when response from secondary server is invalid e.g invalid json format
class InvalidResponseException extends AtException {
  InvalidResponseException(String message) : super(message);
}

/// Exception thrown when a key is invalid
class InvalidAtKeyException extends AtException {
  InvalidAtKeyException(String message) : super(message);
}

/// Exception thrown for issues occurring during data signing or pkam signing operations.
class AtSigningException extends AtException {
  AtSigningException(String message) : super(message);
}

/// Exception thrown for issues occurring during data signing verification or pkam signing verification operations.
class AtSigningVerificationException extends AtException {
  AtSigningVerificationException(String message) : super(message);
}

/// Exception thrown when data provided to a method is invalid.
class InvalidDataException extends AtException {
  InvalidDataException(String message) : super(message);
}

/// Exception thrown for enrollment related exceptions
class AtEnrollmentException extends AtException {
  AtEnrollmentException(String message) : super(message);
}

/// Exception thrown when an Enrollment_id is expired or invalid
class AtInvalidEnrollmentException extends AtException {
  AtInvalidEnrollmentException(String message) : super(message);
}

/// Exception thrown when a client tries to revoke its own enrollment
class AtEnrollmentRevokeException extends AtEnrollmentException {
  AtEnrollmentRevokeException(String message) : super(message);
}

/// Exception thrown when the enrollment requests exceed the limit
/// in the given time window
class AtThrottleLimitExceeded extends AtException {
  AtThrottleLimitExceeded(String message) : super(message);
}

enum ExceptionScenario {
  noNetworkConnectivity,
  rootServerNotReachable,
  secondaryServerNotReachable,
  invalidValueProvided,
  valueExceedingBufferLimit,
  noNamespaceProvided,
  invalidKeyFormed,
  invalidMetadataProvided,
  keyNotFound,
  encryptionFailed,
  decryptionFailed,
  remoteVerbExecutionFailed,
  localVerbExecutionFailed,
  atSignDoesNotExist,
  fetchEncryptionKeys
}

enum Intent {
  syncData,
  shareData,
  fetchData,
  validateKey,
  validateAtSign,
  remoteVerbExecution,
  notifyData,
  encryptData,
  decryptData,
  fetchEncryptionPublicKey,
  fetchEncryptionPrivateKey,
  fetchEncryptionSharedKey,
  fetchSelfEncryptionKey
}
