import 'package:at_auth/src/at_auth_impl.dart';
import 'package:at_auth/src/auth/apkam_signing_scheme.dart';
import 'package:at_auth/src/auth/cram_authenticator.dart';
import 'package:at_auth/src/auth/pkam_authenticator.dart';
import 'package:at_auth/src/enroll/at_enrollment.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_progress.dart';
import 'package:meta/meta.dart';

import 'auth/retry_options.dart';
import 'keys/at_keys.dart';
import 'keys/io/at_keys_io.dart';

/// Interface for onboarding and authentication to a secondary server of an atsign.
///
/// Every method takes the atsign, its atServer and the key source directly, and
/// returns nothing: completing normally *is* the success signal, and failure
/// throws [AtAuthenticationException]. After a successful call, [atLookUp] is
/// the connection that was authenticated, ready to hand to client creation.
abstract interface class AtAuth {
  /// The connection authenticated by the most recent successful call.
  ///
  /// Null until one succeeds, and null again after one fails. This is how a
  /// void-returning call still hands its connection forward — a client built
  /// from it skips a second PKAM handshake.
  AtLookUp? get atLookUp;

  RetryOptions get retryOptions;

  Stream<ProgressEvent> get progressStream;

  /// The APKAM signing scheme every connection this instance builds will
  /// authenticate with.
  ApkamSigningScheme get signing;

  /// Creates an [AtAuth].
  ///
  /// The type of authentication is controlled by [signing]: it selects both the
  /// algorithm the PKAM handshake signs with and which APKAM private key is read
  /// out of the keys. That is the caller's choice, not something inferred from
  /// the material — [AtKeys.generate] mints both a classical and a post-quantum
  /// APKAM key, so a keyset cannot express which one an atServer expects.
  ///
  /// A connection cannot be supplied: at_lookup binds its PKAM key at
  /// construction, so it cannot exist until the keys have been read or minted,
  /// and an activation needs a second one signing with a key that did not exist
  /// when the first was built. [atLookUpFactory] takes over building all of
  /// them; left null, they are built according to [signing].
  factory AtAuth.create({
    RetryOptions? options,
    ApkamSigningScheme signing = ApkamSigningScheme.legacy,
    CramAuthenticator? cramAuthenticator,
    PkamAuthenticator? pkamAuthenticator,
    AtLookUpFactory? atLookUpFactory,
    AtEnrollment Function(AtLookUp)? enrollmentFactory,
  }) {
    return AtAuthImpl(
      retryOptions: options ?? RetryOptions.defaultRetryOptions,
      signing: signing,
      cramAuthenticator: cramAuthenticator,
      pkamAuthenticator: pkamAuthenticator,
      atLookUpFactory: atLookUpFactory,
      enrollmentFactory: enrollmentFactory,
    );
  }

  /// Authenticates an atsign to its atServer with PKAM.
  ///
  /// The keys always come from [atKeysIo] — an [AtKeysIo] implementation over a
  /// file, keychain, or memory.
  ///
  /// [enrollmentId] selects the enrollment to authenticate as; when null the
  /// enrollmentId stored in the keys is used.
  ///
  /// Completing normally means authenticated, and [atLookUp] is the connection
  /// it happened on. Failure throws [AtAuthenticationException] and closes any
  /// connection opened along the way.
  Future<void> authenticate(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo, {
    String? enrollmentId,
  });

  /// Activates an atsign for the first time, using its one-time [cramSecret].
  ///
  /// - Connect, and perform CRAM auth
  /// - Generate the PKAM and encryption keypairs and the APKAM symmetric key
  /// - Submit the first enrollment over the CRAM connection, which the atServer
  ///   auto-approves, and adopt the enrollmentId it issues
  /// - Close that connection, reconnect with the new PKAM key, and PKAM auth
  /// - Persist the keys through [atKeysIo]
  /// - Unless [autoCompleteActivation] is false, call [completeActivation]
  ///
  /// [appName] and [deviceName] name the enrollment the atServer records for
  /// this activation.
  Future<void> onboard(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
    String cramSecret, {
    bool mintLegacy = true,
    bool autoCompleteActivation = true,
    @visibleForTesting String? appName,
    @visibleForTesting String? deviceName,
  });

  /// - Update the encryption public key on the atServer
  /// - Delete the cram secret from the atServer
  ///
  /// Reuses [atLookUp] when a call has already authenticated on this instance;
  /// otherwise authenticates first with the keys in [atKeysIo].
  Future<void> completeActivation(
    Atsign atsign,
    AtRootDomain rootDomain,
    AtKeysIo atKeysIo,
  );

  /// Validates the atsign's atServer status.
  /// - Check that the atsign resolves in the atDirectory
  /// - When [onboarding], require an atServer that is running and NOT yet
  ///   activated (looks for the teapot); otherwise require one already activated
  Future<void> validateAtServer(Atsign atsign, AtRootDomain rootDomain,
      {bool onboarding = false});
}
