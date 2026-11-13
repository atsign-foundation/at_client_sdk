import 'package:at_client/at_client.dart';

import '../keys/passkey_port.dart' show PasskeyCeremonyException;
import '../keys/passkey_record.dart';
import '../keys/prf_support.dart' show PrfUnavailableException;
import '../session/passkey_custody.dart';
import '../session/portal_session.dart';
import '../session/setup_lock.dart' show SetupLockTimeoutException;
import 'js_session.dart';

/// The `AtError.code` for [error]: one string per typed exception the
/// session, custody and passkey layers throw, `internal` for anything else.
String atErrorCode(Object error) => switch (error) {
      PasskeyLostException(:final noPasskeyHere) =>
        noPasskeyHere ? 'no_passkey_here' : 'passkey_lost',
      PasskeyCeremonyException() ||
      PasskeyRecordAuthenticationException() =>
        'passkey_lost',
      PrfUnavailableException() => 'prf_unavailable',
      PkamRefusedException() || AtOpenRefusedException() => 'pkam_refused',
      PublicKeyMismatchException() => 'public_key_mismatch',
      SetupLockTimeoutException() => 'setup_lock_timeout',
      PortalSessionOfflineException() => 'offline',
      OnboardingIncompleteException() ||
      ActivationUnfinishedException() ||
      MissingAtKeysDocumentException() ||
      AtEnrollmentPendingException() =>
        'onboarding_incomplete',
      AtEnrollmentException() => 'enrollment_denied',
      SessionClosedException() => 'closed',
      UnsupportedKeyMaterialException() ||
      UnsupportedPasskeyRecordException() ||
      UnsupportedError() =>
        'unsupported',
      BadKeyException() => 'bad_key',
      _ => 'internal',
    };
