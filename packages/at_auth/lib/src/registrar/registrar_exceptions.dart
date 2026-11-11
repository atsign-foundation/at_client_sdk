import 'package:at_commons/at_commons.dart';

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
