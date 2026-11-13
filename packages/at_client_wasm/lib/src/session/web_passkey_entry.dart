import 'package:at_client/at_client.dart';

import '../keys/indexeddb_store.dart';
import '../keys/passkey_record_keys.dart';
import '../keys/prf_support.dart';
import '../keys/web_passkey_port.dart';
import '../keys/web_prf_environment.dart';
import 'dev_session_options.dart';
import 'enrollment_gateway.dart';
import 'enrollment_pointer_store.dart';
import 'passkey_custody.dart';
import 'passkey_session.dart';
import 'portal_session.dart' show SessionTransport;
import 'session_transport.dart';
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
/// namespace and [device] the enrollment's device name. With [proxyHost] and
/// [proxyPort] every connection goes through that dev proxy.
///
/// Throws [PrfUnavailableException] when the browser or authenticator has no
/// passkey PRF, and the atServer's own errors when activation is refused.
Future<AtClient> onboardNewAtSign(
        {required String atSign,
        required String cram,
        required String app,
        required String rpId,
        required String rpName,
        String device = _defaultDevice,
        String? proxyHost,
        int? proxyPort}) =>
    _withCustody(
        atSign: atSign,
        app: app,
        rpId: rpId,
        rpName: rpName,
        device: device,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        run: (custody, options, transport) => onboardSession(custody,
            atSign: options.atSign,
            cram: cram,
            app: app,
            transport: transport,
            root: options.root));

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
/// the restored public keys are not the published ones, and
/// [MissingAtKeysDocumentException] when the enrollment has no document.
Future<AtClient> passkeyLogin(
        {required String atSign,
        required String app,
        required String rpId,
        required String rpName,
        String? proxyHost,
        int? proxyPort}) =>
    _withCustody(
        atSign: atSign,
        app: app,
        rpId: rpId,
        rpName: rpName,
        device: _defaultDevice,
        proxyHost: proxyHost,
        proxyPort: proxyPort,
        run: (custody, options, transport) => loginSession(custody,
            atSign: options.atSign,
            app: app,
            transport: transport,
            root: options.root));

const _defaultDevice = 'browser';

/// Runs [run] on a [PasskeyCustody] over this browser's passkeys, IndexedDB,
/// locks and atServer transport, and closes the IndexedDB store after.
Future<AtClient> _withCustody(
    {required String atSign,
    required String app,
    required String rpId,
    required String rpName,
    required String device,
    required String? proxyHost,
    required int? proxyPort,
    required Future<AtClient> Function(
            PasskeyCustody, DevSessionOptions, SessionTransport)
        run}) async {
  final options = DevSessionOptions(
      atSign: atSign, app: app, proxyHost: proxyHost, proxyPort: proxyPort);
  final transport = sessionTransport(options);
  final store = await IndexedDbKeyBytesStore.open();
  try {
    final custody = PasskeyCustody(
        kek: PasskeyKek(WebPasskeyPort(rpId: rpId, rpName: rpName),
            prfSupport: PrfSupport(WebPrfEnvironment())),
        pointerReader: LookupEnrollmentPointerReader(
            lookUps: transport.lookUps,
            rootDomain: options.root,
            secondaryAddressFinder: transport.finder),
        gateway: AtAuthEnrollmentGateway(
            transport: transport,
            root: options.root,
            app: app,
            device: device,
            namespaces: {'atkeysv': 'rw', app: 'rw'}),
        credentials: store,
        enrollmentIds: store,
        setupLock: WebSetupLock(),
        persistence: WebStoragePersistence());
    return await run(custody, options, transport);
  } finally {
    store.close();
  }
}
