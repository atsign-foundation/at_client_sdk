import 'package:at_commons/at_commons.dart';

class AtClientException implements Exception {
  String errorCode;
  String errorMessage;
  AtClientException(this.errorCode, this.errorMessage);
}


class InvalidDecryptionKeyException extends AtException {
  InvalidDecryptionKeyException(message) : super(message);
}