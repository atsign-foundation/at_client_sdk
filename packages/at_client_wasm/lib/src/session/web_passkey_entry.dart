import 'package:at_auth/passkey.dart';
import 'package:at_client/passkey.dart';

import '../keys/indexeddb_store.dart';
import '../keys/web_crypto_passkey.dart';
import '../keys/web_passkey_port.dart';
import '../keys/web_prf_environment.dart';
import 'passkey_wiring.dart';
import 'session_transport_options.dart';
import 'web_setup_lock.dart';
import 'web_storage_persistence.dart';

/// Whether this browser can evaluate passkey PRF, as far as it tells.
///
/// [onboardNewAtSign] refuses with a [PrfUnavailableException] before any
/// ceremony when this is false. In a browser that cannot report PRF support,
/// it is false for [prfMissTtl] after a registration recorded a PRF miss,
/// until [clearPrfMiss] clears it.
Future<bool> prfSupported() => PrfSupport(WebPrfEnvironment()).supported();

/// Forgets a recorded PRF miss, so the next [onboardNewAtSign] runs the
/// passkey ceremonies again instead of refusing for the rest of
/// [prfMissTtl].
///
/// For the user's "Try again", for example with another authenticator. Does
/// nothing when no miss is recorded. A browser that reports PRF support
/// decides by that report, recorded miss or not.
void clearPrfMiss() => PrfSupport(WebPrfEnvironment()).tryAgain();

/// Onboards a fresh [atSign] in this browser and returns its passkey session,
/// whose client is PKAM'd before return.
///
/// Registers a passkey (a random WebAuthn `user.id`; [atSign] only in the
/// user name), derives the atSign's APKAM key, record key and pointer name
/// from its PRF output, activates the atSign with [cram], records on the
/// atServer that the activation's completion is due, and writes the sealed
/// @keys document and a public pointer there. Then it deletes the CRAM
/// secret and, once that delete answers, records that it is deleted, then
/// revokes every other approved enrollment, then publishes the encryption
/// public key, then deletes the record that the completion is due. The whole
/// flow holds the atSign's setup lock, so a second tab waits.
///
/// [rpId] and [rpName] name the relying party; [app] is the client's
/// namespace and [device] the enrollment's device name. [transport] says how
/// connections reach atServers, by default directly.
///
/// An onboarding that fails before it writes the pointer throws the failure
/// as it is, and any passkey it registered is reported to the browser as
/// unknown. It is run again with the same [cram] while the CRAM secret is
/// live, which registers a new passkey and revokes every other approved
/// enrollment of the Atsign, the failed run's included.
///
/// One that fails with an exception once it has written the pointer, while
/// it deletes the CRAM secret, records that, revokes, publishes, deletes the
/// completion-due record or opens the client, throws a
/// [PasskeyOnboardingIncompleteException] naming the Atsign, whose cause is
/// that failure, and reports nothing to the browser. [passkeyLogin] with the
/// passkey then finishes the onboarding, unless it refuses another published
/// encryption public key with [PublicKeyMismatchException]; it opens the
/// onboarding's enrollment and saves the passkey hints if they are not
/// saved. An [Error] is thrown as it is wherever it happens, so it does not
/// say whether the pointer was written: try [passkeyLogin] with the passkey
/// first. A failed write of the hints does not fail the onboarding: it is
/// logged as a warning, the session is returned, and the next
/// [passkeyLogin] saves them.
/// [passkeyLogin] also finishes an onboarding that stopped after writing the
/// document and pointer, while its completion is due. Nothing is kept in
/// this browser until the CRAM secret is deleted.
///
/// Throws [PrfUnavailableException] when the browser or authenticator has no
/// passkey PRF, [SetupLockTimeoutException] when another tab holds the setup
/// lock too long, [IndexedDbException] when this browser's passkey database
/// will not open, before any passkey is registered, the atServer's own errors
/// when activation is refused, and [PasskeyOnboardingIncompleteException] as
/// above.
///
/// Stopping the session, or its client, closes the passkey vault it holds.
Future<PasskeySession> onboardNewAtSign(
        {required String atSign,
        required String cram,
        required String app,
        required String rpId,
        required String rpName,
        String device = _defaultDevice,
        SessionTransportOptions? transport}) =>
    _withCustody(
        app: app,
        rpId: rpId,
        rpName: rpName,
        device: device,
        options: transport,
        run: (custody) => custody.onboard(atSign: atSign, cram: cram));

/// Opens [atSign]'s client with its passkey and returns its passkey session,
/// whose client is PKAM'd before return.
///
/// [atSign] is always required: the passkey proves it, and a wrong one finds
/// no pointer. A device that remembers [atSign]'s passkey and enrollment goes
/// straight to PKAM; one that does not asserts any discoverable passkey and
/// finds the enrollment through the public pointer. A remembered credential
/// id or enrollment id that IndexedDB cannot read, or an enrollment id whose
/// stored bytes are not UTF-8, counts as not remembered, and a failed write
/// of the passkey hints is logged as a warning and the session returned.
///
/// Throws [PasskeyLostException] when the passkey cannot open [atSign] (no
/// credential, no pointer, PKAM refused), [PublicKeyMismatchException] when
/// the document's APKAM public key is not the passkey's, or when a published
/// encryption public key is not the document's, unless the onboarding
/// recorded that its own delete of the CRAM secret answered and its
/// completion is still due, [MissingAtKeysDocumentException] when the
/// enrollment has no document, [SetupLockTimeoutException] when another tab
/// holds the setup lock too long, [IndexedDbException] when this browser's
/// passkey database will not open, and what reading the completion-due
/// record or finishing an unfinished onboarding throws, such as the
/// `AtEnrollmentException` of a revoke that leaves another approved
/// enrollment; the next login tries again.
///
/// A [PasskeyLostException] whose cause is a `PasskeyCeremonyException` means
/// the prompt failed, and the user may simply have cancelled it: WebAuthn
/// reports a cancel and a missing passkey the same way. Nothing is deleted,
/// revoked or cleared after a failed or cancelled prompt, so the app can offer
/// "Try again".
///
/// [PrfUnavailableException] and [SetupLockTimeoutException] are thrown as
/// they are, not wrapped in [PasskeyLostException].
///
/// Stopping the session, or its client, closes the passkey vault it holds.
Future<PasskeySession> passkeyLogin(
        {required String atSign,
        required String app,
        required String rpId,
        required String rpName,
        SessionTransportOptions? transport}) =>
    _withCustody(
        app: app,
        rpId: rpId,
        rpName: rpName,
        device: _defaultDevice,
        options: transport,
        run: (custody) => custody.open(atSign: atSign));

const _defaultDevice = 'browser';

/// Runs [run] on a [PasskeyCustody] over this browser's passkeys, IndexedDB,
/// locks and atServer transport, and closes the IndexedDB store after.
Future<PasskeySession> _withCustody(
    {required String app,
    required String rpId,
    required String rpName,
    required String device,
    required SessionTransportOptions? options,
    required Future<PasskeySession> Function(PasskeyCustody) run}) async {
  final server = passkeyServerSide(options: options, app: app, device: device);
  return runClosingStore(
      openEntryHintStore,
      (store) => run(PasskeyCustody(
          prf: PasskeyPrf(WebPasskeyPort(rpId: rpId, rpName: rpName),
              prfSupport: PrfSupport(WebPrfEnvironment())),
          pointerReader: server.pointerReader,
          gateway: server.gateway,
          credentials: store,
          enrollmentIds: store,
          setupLock: WebSetupLock(),
          setupLockPrefix: WebSetupLock.namePrefix,
          persistence: WebStoragePersistence(),
          deriver: WebCryptoKeyDeriver())));
}

/// Opens the hint store [onboardNewAtSign] and [passkeyLogin] run on, this
/// browser's passkey database by default.
///
/// Public only so that tests can see the store an entry point opened; the
/// package does not export it.
Future<IndexedDbHintStore> Function() openEntryHintStore =
    IndexedDbHintStore.open;

/// Runs [run] on the hint store [openStore] opens, and closes that store once
/// [run] has returned or thrown; what [run] throws propagates.
///
/// Public only so that tests reach it; the package does not export it.
Future<T> runClosingStore<T>(Future<IndexedDbHintStore> Function() openStore,
    Future<T> Function(IndexedDbHintStore store) run) async {
  final store = await openStore();
  try {
    return await run(store);
  } finally {
    store.close();
  }
}
