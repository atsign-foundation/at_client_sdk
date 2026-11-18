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
/// ceremony when this is false.
Future<bool> prfSupported() => PrfSupport(WebPrfEnvironment()).supported();

/// Onboards a fresh [atSign] in this browser and returns its passkey session,
/// whose client is PKAM'd before return.
///
/// Registers a passkey (a random WebAuthn `user.id`; [atSign] only in the
/// user name), derives the atSign's APKAM key, record key and pointer name
/// from its PRF output, activates the atSign with [cram], writes the sealed
/// @keys document and a public pointer on the atServer, revokes every other
/// approved enrollment, and only then publishes the encryption public key and
/// deletes the CRAM secret. The whole flow holds the atSign's setup lock, so a
/// second tab waits.
///
/// [rpId] and [rpName] name the relying party; [app] is the client's
/// namespace and [device] the enrollment's device name. [transport] says how
/// connections reach atServers, by default directly.
///
/// An onboarding that fails before the CRAM secret is deleted can be run
/// again with the same [cram], which registers a new passkey and revokes the
/// enrollment the failed run left; the passkey that failed is reported to the
/// browser as unknown when the failure came before the activation was being
/// completed. Once the CRAM secret is deleted,
/// [passkeyLogin] finishes the onboarding, including when the client failed
/// to open. Nothing is kept in this browser until the CRAM secret is deleted.
///
/// Throws [PrfUnavailableException] when the browser or authenticator has no
/// passkey PRF, [SetupLockTimeoutException] when another tab holds the setup
/// lock too long, and the atServer's own errors when activation is refused.
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
/// finds the enrollment through the public pointer.
///
/// Throws [PasskeyLostException] when the passkey cannot open [atSign] (no
/// credential, no pointer, PKAM refused), [PublicKeyMismatchException] when
/// the restored public keys are not the published ones,
/// [MissingAtKeysDocumentException] when the enrollment has no document, and
/// [SetupLockTimeoutException] when another tab holds the setup lock too long.
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
  final store = await IndexedDbHintStore.open();
  try {
    return await run(PasskeyCustody(
        prf: PasskeyPrf(WebPasskeyPort(rpId: rpId, rpName: rpName),
            prfSupport: PrfSupport(WebPrfEnvironment())),
        pointerReader: server.pointerReader,
        gateway: server.gateway,
        credentials: store,
        enrollmentIds: store,
        setupLock: WebSetupLock(),
        setupLockPrefix: WebSetupLock.namePrefix,
        persistence: WebStoragePersistence(),
        deriver: WebCryptoKeyDeriver()));
  } finally {
    store.close();
  }
}
