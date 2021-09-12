import 'package:at_client/src/exception/at_client_error_codes.dart';

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
  AtKeyException(message) : super(at_client_error_codes['AtKeyException'], message);
}

class AtNamespaceException extends AtClientException {
  AtNamespaceException(message) : super(at_client_error_codes['NamespaceException'], message);
}
