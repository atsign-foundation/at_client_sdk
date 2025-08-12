class AtLoginException implements Exception {
  var errorMessage;
  var errorDescription;
}

class ResponseTimeOutException extends AtLoginException {}
