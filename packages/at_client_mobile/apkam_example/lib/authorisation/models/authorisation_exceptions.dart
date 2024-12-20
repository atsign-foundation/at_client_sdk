class AuthorisationException implements Exception {
  AuthorisationException(this.message);

  final String message;

  @override
  String toString() {
    return 'AuthorisationException: $message';
  }
}

final class InvalidSppException extends AuthorisationException {
  InvalidSppException() : super('SPP must be alphanumeric and 6 to 16 characters long');
}

final class OtpGenerationException extends AuthorisationException {
  OtpGenerationException(String serverMessage) : super('Failed to generate OTP: $serverMessage');
}

final class UnexpectedResponseException extends AuthorisationException {
  UnexpectedResponseException(String response) : super('Unexpected server response: $response');
}

final class FailedToApproveException extends AuthorisationException {
  FailedToApproveException() : super('Failed to approve enrollment request');
}

final class FailedToDenyException extends AuthorisationException {
  FailedToDenyException() : super('Failed to deny enrollment request');
}

final class FailedToRevokeException extends AuthorisationException {
  FailedToRevokeException() : super('Failed to revoke enrollment request');
}
