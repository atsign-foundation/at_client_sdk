import 'package:at_client/src/exception/at_client_error_codes.dart';

@Deprecated('Moving this to at_commons package')
class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);

  @override
  String toString() {
    return '$errorCode: $errorMessage';
  }
}

@Deprecated('Moving this to at_commons package')
class AtKeyException extends AtClientException {
  AtKeyException(message)
      : super(atClientErrorCodes['AtKeyException'], message);
}
