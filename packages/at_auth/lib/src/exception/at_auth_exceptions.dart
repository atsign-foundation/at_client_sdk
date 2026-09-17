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
