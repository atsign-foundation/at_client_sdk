class AuthorisationException implements Exception {
  AuthorisationException(this.message);

  final String message;

  @override
  String toString() {
    return 'AuthorisationException: $message';
  }
}

class InvalidSppException extends AuthorisationException {
  InvalidSppException() : super('SPP must be alphanumeric and 6 to 16 characters long');
}

class OtpGenerationException extends AuthorisationException {
  OtpGenerationException(String serverMessage) : super('Failed to generate OTP: $serverMessage');
}

class UnexpectedResponseException extends AuthorisationException {
  UnexpectedResponseException(String response) : super('Unexpected server response: $response');
}

class FailedToApproveException extends AuthorisationException {
  FailedToApproveException() : super('Failed to approve enrollment request');
}

class FailedToDenyException extends AuthorisationException {
  FailedToDenyException() : super('Failed to deny enrollment request');
}

class FailedToRevokeException extends AuthorisationException {
  FailedToRevokeException() : super('Failed to revoke enrollment request');
}
