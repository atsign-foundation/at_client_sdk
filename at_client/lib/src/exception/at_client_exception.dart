import 'package:at_commons/at_commons.dart';

class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);
}

/// The base class for any [AtKey] specific exceptions.
class AtKeyException extends AtClientException {
  AtKeyException(message) : super(error_codes['AtKeyException'], message);
}

/// Raised when @sign user does not have permission's to update the key.
class PermissionDeniedException extends AtClientException {
  PermissionDeniedException(message) : super(error_codes['PermissionDeniedException'], message);
}
