@Deprecated('Moved to at_commons package')
class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;

  AtClientException(this.errorCode, this.errorMessage);

  @override
  String toString() {
    return '$errorCode: $errorMessage';
  }
}

@Deprecated('Moved to at_commons package')
class AtKeyException extends AtClientException {
  AtKeyException(errorCode, message) : super(errorCode, message);
}
