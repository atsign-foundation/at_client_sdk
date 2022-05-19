@Deprecated(
    'Moved AtClientException to at_commons package [at_commons/src/exception/at_exceptions.dart]')
class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);

  @override
  String toString() {
    return '$errorCode: $errorMessage';
  }
}

@Deprecated(
    'Moved AtKeyException to at_commons package [at_commons/src/exception/at_exceptions.dart]')
class AtKeyException extends AtClientException {
  AtKeyException(message) : super('AT0023', message);
}
