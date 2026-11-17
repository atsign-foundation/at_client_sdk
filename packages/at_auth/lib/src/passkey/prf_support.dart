import 'package:at_commons/at_commons.dart';

/// The message shown when passkey PRF is unavailable.
const prfUnsupportedMessage = 'This browser or authenticator does not support '
    'passkey PRF. Use a supported browser.';

/// How long a recorded PRF miss is honoured.
const prfMissTtl = Duration(days: 30);

/// Thrown when the authenticator does not support or return a valid PRF result.
class PrfUnavailableException extends AtException {
  /// Initializes the exception with an error [message].
  PrfUnavailableException(super.message);

  /// Returns a string representation of this exception.
  @override
  String toString() => 'PrfUnavailableException: $message';
}

/// The browser facilities [PrfSupport] reads and writes.
abstract class PrfEnvironment {
  /// `PublicKeyCredential.getClientCapabilities()['extension:prf']`, or null
  /// when that API does not exist.
  Future<bool?> clientCapabilityPrf();

  /// When a PRF miss was recorded, or null when none was.
  DateTime? missRecordedAt();

  /// Records a PRF miss at [at].
  void recordMiss(DateTime at);

  /// Forgets any recorded PRF miss.
  void clearMiss();

  /// The current time.
  DateTime now();
}

/// Whether this browser can evaluate passkey PRF.
///
/// The client capabilities API decides when it exists; otherwise a recorded
/// PRF miss counts against support for [prfMissTtl].
class PrfSupport {
  /// Initializes the check over [environment].
  PrfSupport(this.environment);

  /// The browser facilities behind the check.
  final PrfEnvironment environment;

  /// Whether PRF is, as far as the browser tells, supported.
  Future<bool> supported() async {
    final capability = await environment.clientCapabilityPrf();
    if (capability != null) return capability;
    final missAt = environment.missRecordedAt();
    if (missAt == null) return true;
    final age = environment.now().difference(missAt);
    return age.isNegative || age >= prfMissTtl;
  }

  /// Throws [PrfUnavailableException] with a user-facing message unless
  /// [supported].
  Future<void> require() async {
    if (!await supported()) {
      throw PrfUnavailableException(prfUnsupportedMessage);
    }
  }

  /// Records that an authenticator definitely does not support PRF.
  void recordMiss() => environment.recordMiss(environment.now());

  /// Forgets a recorded PRF miss, so the next ceremony is attempted.
  void tryAgain() => environment.clearMiss();
}
