class UnsupportedEnvelopeException implements Exception {
  final String message;
  UnsupportedEnvelopeException(this.message);

  @override
  String toString() => 'UnsupportedEnvelopeException: $message';
}

class EnvelopeAtSignMismatchException implements Exception {
  final String message;
  EnvelopeAtSignMismatchException(this.message);

  @override
  String toString() => 'EnvelopeAtSignMismatchException: $message';
}

class NoMatchingUnlockException implements Exception {
  final String message;
  NoMatchingUnlockException(this.message);

  @override
  String toString() => 'NoMatchingUnlockException: $message';
}

class EnvelopeUnlockFailedException implements Exception {
  final String message;
  EnvelopeUnlockFailedException(this.message);

  @override
  String toString() => 'EnvelopeUnlockFailedException: $message';
}

class EnvelopeContentKeyMismatchException implements Exception {
  final String message;
  EnvelopeContentKeyMismatchException(this.message);

  @override
  String toString() => 'EnvelopeContentKeyMismatchException: $message';
}
