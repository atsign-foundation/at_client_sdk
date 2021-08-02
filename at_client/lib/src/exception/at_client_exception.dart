import 'package:at_commons/at_commons.dart';

class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);
}

/// The base class for any [AtKey] specific exceptions.
class AtKeyException extends AtException {
  AtKeyException(message) : super(message);
}

/// Raised when key is invalid.
class InvalidAtkeyException extends AtKeyException {
  InvalidAtkeyException(message) : super(message);
}

/// Raised when @sign user does not have permission's to update the key.
class PermissionDeniedException extends AtKeyException {
  PermissionDeniedException(message) : super(message);
}

/// Raised when metadata of the key has invalid values
class InvalidMetadataException extends AtKeyException {
  InvalidMetadataException(message) : super(message);
}
