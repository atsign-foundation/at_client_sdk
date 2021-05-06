class AtClientException implements Exception {
  String? errorCode;
  String? errorMessage;
  AtClientException(this.errorCode, this.errorMessage);
}
