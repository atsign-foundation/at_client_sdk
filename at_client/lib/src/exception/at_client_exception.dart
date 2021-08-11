import 'package:at_commons/at_commons.dart';

class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);

  @override
  String toString() {
    return '$errorCode: $errorMessage';
  }
}

class AtKeyException extends AtClientException {
  AtKeyException(message) : super(error_codes['AtKeyException'], message);
}
