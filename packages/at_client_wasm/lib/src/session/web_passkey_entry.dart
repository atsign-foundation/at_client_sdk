import 'package:at_auth/passkey.dart';
import 'package:at_client/at_client.dart';
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

/// Onboards a fresh [atSign] in this browser and returns its client, PKAM'd
/// before return.
///
/// Registers a passkey (a random WebAuthn `user.id`; [atSign] only in the
/// user name), derives the atSign's APKAM key, record key and pointer name
/// from its PRF output, activates the atSign with [cram] and files the sealed
/// @keys document and a public pointer on the atServer. The whole flow holds
/// the atSign's setup lock, so a second tab waits.
///
/// [rpId] and [rpName] name the relying party; [app] is the client's
/// namespace and [device] the enrollment's device name. [transport] says how
/// connections reach atServers, by default directly.
///
/// Throws [PrfUnavailableException] when the browser or authenticator has no
/// passkey PRF, [SetupLockTimeoutException] when another tab holds the setup
/// lock too long, [IndexedDbException] when this browser's IndexedDB fails
/// before this call activates the atSign, and the atServer's own errors when
/// activation is refused. An [OnboardingIncompleteException] carries the
/// pending onboarding to resume; when writing the device's passkey hints
/// fails after this call activates the atSign, its cause is the
/// [IndexedDbException].
/// A client that fails to open after the records are written ends the
/// onboarding: its own error propagates, the IndexedDB store is closed and
/// the atSign is ready for [passkeyLogin].
///
/// An earlier onboarding that is still pending is resumed first, without
/// [cram]. When the atServer explicitly refuses that onboarding's PKAM, its
/// record is dropped and this onboarding carries on with [cram]. Any other
/// failure keeps the record: a failed or cancelled prompt for its passkey is a
/// [PasskeyLostException] whose cause is a `PasskeyCeremonyException` (the
/// user may simply have cancelled it), and a PKAM refusal during an explicit
/// [PendingOnboarding.resume] is a [PasskeyLostException] too. The app then
/// offers "Try again" and "Discard" ([discardPendingOnboarding]) and never
/// discards on its own; see `docs/projects/wasm/browser-onboarding.md`.
///
/// [PrfUnavailableException] and [SetupLockTimeoutException] are thrown as
/// they are, not wrapped in [PasskeyLostException].
Future<AtClient> onboardNewAtSign(
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

/// Opens [atSign]'s client with its passkey and returns it, PKAM'd before
/// return.
///
/// [atSign] is always required: the passkey proves it, and a wrong one finds
/// no pointer. A device that remembers [atSign]'s passkey and enrollment goes
/// straight to PKAM; one that does not asserts any discoverable passkey and
/// finds the enrollment through the public pointer.
///
/// Throws [PasskeyLostException] when the passkey cannot open [atSign] (no
/// credential, no pointer, PKAM refused), [PublicKeyMismatchException] when
/// the restored public keys are not the published ones,
/// [MissingAtKeysDocumentException] when the enrollment has no document,
/// [SetupLockTimeoutException] when another tab holds the setup lock too long,
/// and [IndexedDbException] when this browser's IndexedDB fails.
///
/// A pending onboarding the atServer explicitly refuses is dropped and the
/// login carries on; any other failure to resume it keeps its record.
///
/// A [PasskeyLostException] whose cause is a `PasskeyCeremonyException` means
/// the prompt failed, and the user may simply have cancelled it: WebAuthn
/// reports a cancel and a missing passkey the same way. Nothing is deleted,
/// revoked or cleared after a failed or cancelled prompt, so the app offers
/// "Try again" and "Discard" ([discardPendingOnboarding]) and never discards
/// on its own; see `docs/projects/wasm/browser-onboarding.md`.
///
/// [PrfUnavailableException] and [SetupLockTimeoutException] are thrown as
/// they are, not wrapped in [PasskeyLostException].
Future<AtClient> passkeyLogin(
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

/// Deletes [atSign]'s pending onboarding record: the "Discard" choice after a
/// pending onboarding cannot be opened.
///
/// Runs no ceremony and makes no atServer call; it takes the atSign's setup
/// lock and closes the IndexedDB store. Calling it with no pending record is
/// a no-op: nothing is deleted and the hints stay. Otherwise it deletes the
/// record, and deletes the atSign's remembered passkey and enrollment hints
/// only when the stored enrollment id equals the record's enrollment id;
/// hints naming another enrollment stay. If no @keys document was written,
/// the record held the only copy of the keys and the atSign must be reset
/// with a new CRAM. Never call it without the user's choice.
///
/// Throws [SetupLockTimeoutException] when another tab holds the setup lock
/// too long, and [IndexedDbException] when this browser's IndexedDB fails.
Future<void> discardPendingOnboarding(String atSign) async =>
    discardPendingOnboardingIn(await IndexedDbHintStore.open(), atSign);

/// [discardPendingOnboarding] on an open [store], which it closes.
///
/// Public for tests; not exported from the package.
Future<void> discardPendingOnboardingIn(
        IndexedDbHintStore store, String atSign) =>
    closingStoreAfter(store, () {
      final canonical = canonicalPasskeyAtSign(atSign);
      return WebSetupLock()
          .run(setupLockName(WebSetupLock.namePrefix, canonical), () async {
        final record = await store.get(canonical);
        if (record == null) return;
        await store.delete(canonical);
        if (await store.enrollmentId(canonical) == record.enrollmentId) {
          await store.deleteHints(canonical);
        }
      });
    });

const _defaultDevice = 'browser';

/// Runs [run] on a [PasskeyCustody] over this browser's passkeys, IndexedDB,
/// locks and atServer transport, and closes the IndexedDB store after.
Future<AtClient> _withCustody(
    {required String app,
    required String rpId,
    required String rpName,
    required String device,
    required SessionTransportOptions? options,
    required Future<AtClient> Function(PasskeyCustody) run}) async {
  final server = passkeyServerSide(options: options, app: app, device: device);
  final store = await IndexedDbHintStore.open();
  return closingStoreAfter(
      store,
      () => run(PasskeyCustody(
          prf: PasskeyPrf(WebPasskeyPort(rpId: rpId, rpName: rpName),
              prfSupport: PrfSupport(WebPrfEnvironment())),
          pointerReader: server.pointerReader,
          gateway: server.gateway,
          credentials: store,
          enrollmentIds: store,
          setupLock: WebSetupLock(),
          setupLockPrefix: WebSetupLock.namePrefix,
          persistence: WebStoragePersistence(),
          pendingStore: store,
          deriver: WebCryptoKeyDeriver())));
}

/// Runs [run] and closes [store] after, whether it returns or throws. An
/// [OnboardingIncompleteException] keeps the store open for its pending
/// onboarding, which closes it once resumed, abandoned or ended by a failed
/// open.
///
/// Public for tests; not exported from the package.
Future<T> closingStoreAfter<T>(
    IndexedDbHintStore store, Future<T> Function() run) async {
  var handedOff = false;
  try {
    return await run();
  } on OnboardingIncompleteException catch (e) {
    e.pending.releaseWith(store.close);
    handedOff = true;
    rethrow;
  } finally {
    if (!handedOff) store.close();
  }
}
