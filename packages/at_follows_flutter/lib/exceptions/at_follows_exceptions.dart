class AtFollowsException implements Exception {
  var errorMessage;
  var errorDescription;
}

class ResponseTimeOutException extends AtFollowsException {}
