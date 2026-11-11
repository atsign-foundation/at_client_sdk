import 'package:at_commons/at_commons.dart';

class AtAuthenticationException extends AtException {
  AtAuthenticationException(super.message);
}

class AtKeysFileOverwriteException extends AtException {
  AtKeysFileOverwriteException(super.message);
}

class AtKeysParseException extends AtException {
  AtKeysParseException(super.message);
}

/// An atKeys document that is not a JSON object: [reason] says why, in the
/// JSON parser's words when it did not parse, and [position] is the 1-based
/// character where the parser stopped.
///
/// It holds none of the document's text, in its fields or its message.
class AtKeysFormatException extends FormatException {
  /// Why the document is not a JSON object.
  final String reason;

  /// The 1-based character where the parser stopped; null when the document
  /// parsed, as JSON that is not an object, or the parser named none.
  final int? position;

  // NOTE: source stays null; the parser's source is the document's text.
  AtKeysFormatException._(String message, this.reason, this.position)
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
        position);
  }

  /// [what] parsed, as JSON that is not an object.
  factory AtKeysFormatException.notAnObject(String what) =>
      AtKeysFormatException._(
          '$what is not a JSON object', 'not a JSON object', null);

  @override
  String toString() => 'AtKeysFormatException: $message';
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

/// Why a [RegistrarException] was thrown.
enum RegistrarFailure {
  /// The super API key was rejected (HTTP 401/403).
  authentication,

  /// The registrar reported `{"status": "error"}`.
  unavailable,

  /// The registrar returned a non-200 status this call did not expect.
  unexpectedStatus,

  /// The response body was not JSON, or not the shape this call expects.
  malformedResponse,

  /// A register call returned `{"status": "success"}` without a `cramkey`.
  noCramKey,

  /// The request did not complete within its configured timeout.
  timeout,

  /// The response body exceeded the configured size cap.
  responseTooLarge,

  /// The request failed before a response arrived: the connection was
  /// refused, DNS resolution failed, or the connection dropped mid-request.
  network,
}

/// A registrar call failed: an unexpected status code, or a response whose
/// shape the caller cannot use.
///
/// [message] may contain [endpoint] and [statusCode], but never the server's
/// `message` field, any other part of the response body, a cramkey or the
/// super API key, so a registrar error can be logged or surfaced without
/// leaking what the server said.
class RegistrarException extends AtException {
  /// The API path this call was made to, e.g. `/register-atsign/`.
  final String endpoint;

  /// The HTTP status code the registrar returned, when one was received.
  final int? statusCode;

  /// Why this call failed.
  final RegistrarFailure reason;

  RegistrarException(
    super.message, {
    required this.endpoint,
    this.statusCode,
    required this.reason,
  });
}
