import 'package:at_commons/at_commons.dart';

class AtAuthenticationException extends AtException {
  AtAuthenticationException(super.message);
}

/// An atServer's `error:` reply to a `from:`, `pkam:` or `cram:`, which
/// ended the authentication: the message carries the reply.
class AtAuthErrorReplyException extends UnAuthenticatedException {
  /// The code the reply names, or null when it names none.
  final String? errorCode;

  AtAuthErrorReplyException(super.message, {required this.errorCode});
}

/// The enrollment an enrollment wait was waiting on has expired, or its
/// atServer no longer holds it, so no approval can follow.
///
/// It is also an [AtInvalidEnrollmentException], the type at_commons gives
/// AT0029, so a catch of either type catches it.
class AtEnrollmentExpiredException extends AtEnrollmentException
    implements AtInvalidEnrollmentException {
  AtEnrollmentExpiredException(super.message);
}

/// The atServer denied the enrollment an enrollment wait was waiting on
/// (AT0025), so no approval can follow.
///
/// No other end of the wait throws this type.
class AtEnrollmentDeniedException extends AtEnrollmentException {
  AtEnrollmentDeniedException(super.message);
}

class AtKeysFileOverwriteException extends AtException {
  AtKeysFileOverwriteException(super.message);
}

class AtKeysParseException extends AtException {
  AtKeysParseException(super.message);
}

/// An atKeys document that is not a JSON object, or not one of the shape it
/// must have: [reason] says why, in the JSON parser's words when it did not
/// parse, and [position] is the 1-based character where the parser stopped.
///
/// It holds none of the document's text, in its fields or its message.
class AtKeysFormatException extends FormatException {
  /// Why the document is refused: the parser's words, or, when [isJson],
  /// what the document is, such as "not a JSON object".
  final String reason;

  /// The 1-based character where the parser stopped; null when the document
  /// parsed as JSON, or the parser named none.
  final int? position;

  /// Whether the document parsed, as JSON that is not an object or not one
  /// of the shape it must have, or as the other kind of data
  /// [AtKeysFormatException.badField] was given, such as a legacy header.
  final bool isJson;

  // NOTE: source stays null; the parser's source is the document's text.
  AtKeysFormatException._(
      String message, this.reason, this.position, this.isJson)
      : super(message, null, position == null ? null : position - 1);

  /// [what] did not parse: [parserError] is the JSON parser's own exception.
  factory AtKeysFormatException.notJson(
      String what, FormatException parserError) {
    final offset = parserError.offset;
    final position = offset == null ? null : offset + 1;
    return AtKeysFormatException._(
        '$what is not valid JSON: ${parserError.message}'
        '${position == null ? '' : ' (at character $position)'}',
        parserError.message,
        position,
        false);
  }

  /// [what] parsed, as JSON that is not an object.
  factory AtKeysFormatException.notAnObject(String what) =>
      AtKeysFormatException._(
          '$what is not a JSON object', 'not a JSON object', null, true);

  /// [what] parsed, as [kind] whose [field] is missing or not [requirement].
  ///
  /// [kind] says what the data is, and is 'a JSON object' unless the data is
  /// something else, such as a legacy header that is not JSON.
  factory AtKeysFormatException.badField(
      String what, String field, String requirement,
      {String kind = 'a JSON object'}) {
    final reason = '$kind whose $field is not $requirement';
    return AtKeysFormatException._('$what is $reason', reason, null, true);
  }

  @override
  String toString() => 'AtKeysFormatException: $message';
}

/// A passphrase envelope refused for its passphrase: none was given, or the
/// one given does not open it. Every other refusal of an envelope, such as a
/// version or key derivation this build cannot use, is a plain
/// [AtDecryptionException] whose message says what is wrong.
class AtKeysPassphraseException extends AtDecryptionException {
  AtKeysPassphraseException(super.message);
}

class AtKeysValidationException extends AtException {
  AtKeysValidationException(super.message);
}

class AtKeysUnsupportedVersionException extends AtKeysValidationException {
  AtKeysUnsupportedVersionException(super.message);
}

class AtKeysUnsupportedAlgorithmException extends AtKeysValidationException {
  AtKeysUnsupportedAlgorithmException(super.message);
}

class AtKeysProtectionException extends AtKeysValidationException {
  AtKeysProtectionException(super.message);
}

class AtKeysEnrollmentException extends AtKeysValidationException {
  AtKeysEnrollmentException(super.message);
}

/// The key source holds nothing for this atSign **yet** — a cold start, not a
/// fault.
///
/// This is the one read failure a caller is expected to treat as an ordinary
/// absence. Every other way [AtKeysIo.read] can fail — a truncated or corrupt
/// document, a passphrase that was not supplied, a decode or validation
/// refusal — means the material may well exist and this process cannot see it,
/// which is a different thing entirely and must not be reported as "holds
/// nothing".
///
/// Without the distinction a reader can only catch everything and answer null,
/// so an unreadable keyfile is indistinguishable from an empty one. In
/// at_client that surfaced as an nskey private read as merely absent, and
/// since the notification park landed, as a message held for a filing that can
/// never arrive.
class AtKeysSourceAbsentException extends AtException {
  AtKeysSourceAbsentException(super.message);
}

class AtKeysNotInMemoryException extends AtKeysSourceAbsentException {
  AtKeysNotInMemoryException(super.message);
}
