import 'dart:async' show Timer;
import 'dart:convert' show jsonDecode;

import 'package:at_client/at_client.dart'
    show
        AtKey,
        AtValue,
        DeleteRequestOptions,
        EnrollmentConstants,
        GetRequestOptions,
        PutRequestOptions;
import 'package:at_client/src/mixins/apkam_signing.dart' show ApkamSigning;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/client_key_bundle.dart';
import 'package:crypton/crypton.dart' show RSAKeypair, RSAPrivateKey;
import 'package:uuid/uuid.dart' show Uuid;

/// A client identity (clientId + keypair) that an app chose to persist via
/// [PairwiseClientRegistration.saveClientKeys] /
/// [PairwiseClientRegistration.loadClientKeys].
class PersistedClientKeys {
  final String clientId;
  final String rsaPublicKey;
  final String rsaPrivateKey;

  PersistedClientKeys({
    required this.clientId,
    required this.rsaPublicKey,
    required this.rsaPrivateKey,
  });
}

/// Per-client registration for same-atSign secret sharing.
///
/// Each client generates a random [clientId] and a keypair, and publishes a
/// signed [ClientKeyBundle] as a *hidden public key* in its enrollment's
/// reserved namespace:
///
///     public:__pqkb-<clientId>.<enrollmentId>.a.__e@atsign
///
/// Placement gives the bundle its properties:
/// - only the owning enrollment can write into `<enrollmentId>.a.__e`, and
///   the bundle is additionally APKAM-signed (see [EnvelopeSigning]);
/// - hidden public keys (`public:__` prefix) are not enumerable by
///   unauthenticated scans or by other atSigns, but every authenticated
///   client of this atSign can discover them with `showHiddenKeys`,
///   regardless of its enrollment namespaces.
///
/// By default the identity is ephemeral: held in memory, published with
/// [bundleTtl], republished while this client runs, and gone when the
/// process ends. Apps that want a stable clientId across restarts supply
/// [loadClientKeys] / [saveClientKeys].
mixin PairwiseClientRegistration on ApkamSigning, EnvelopeSigning {
  /// How long a published bundle lives on the atServer. While registered,
  /// the bundle is republished at half this interval.
  Duration bundleTtl = Duration(hours: 24);

  /// Supply to give this client a stable identity across restarts.
  /// Called once, before generating a fresh identity; return null to
  /// generate fresh.
  Future<PersistedClientKeys?> Function()? loadClientKeys;

  /// Supply to persist a freshly generated identity (e.g. to the platform
  /// keystore / biometric storage — that is the app's concern).
  Future<void> Function(PersistedClientKeys keys)? saveClientKeys;

  String? _clientId;
  RSAKeypair? _keyPair;
  ClientKeyBundle? _myBundle;
  Timer? _republishTimer;

  /// This client's random per-client id. Throws [StateError] until
  /// [registerClient] has completed.
  String get clientId {
    if (_clientId == null) {
      throw StateError('registerClient() has not been called');
    }
    return _clientId!;
  }

  bool get isRegistered => _myBundle != null;

  /// The bundle this client most recently published.
  ClientKeyBundle? get myBundle => _myBundle;

  /// The keypair backing this client's published bundle.
  RSAKeypair get clientKeyPair {
    if (_keyPair == null) {
      throw StateError('registerClient() has not been called');
    }
    return _keyPair!;
  }

  String get _bundleKeyUri => 'public:__pqkb-$clientId.$enrollmentId'
      '.${EnrollmentConstants.perEnrollmentApproved}'
      '${atClient.getCurrentAtSign()}';

  /// Generates (or loads, via [loadClientKeys]) this client's identity,
  /// publishes its signed [ClientKeyBundle], and keeps republishing it at
  /// [bundleTtl] / 2 until [deregisterClient] is called.
  ///
  /// Also ensures this enrollment's APKAM public signing key is published
  /// ([ApkamSigning.publishPublicSigningKey]) so that other clients can
  /// verify the bundle's signature.
  ///
  /// Note: generating an RSA keypair in pure Dart takes on the order of a
  /// second; it happens at most once per [registerClient] call.
  Future<ClientKeyBundle> registerClient() async {
    if (_clientId == null) {
      final loaded = await loadClientKeys?.call();
      if (loaded != null) {
        _clientId = loaded.clientId;
        _keyPair = RSAKeypair(RSAPrivateKey.fromString(loaded.rsaPrivateKey));
      } else {
        _clientId = Uuid().v4();
        _keyPair = RSAKeypair.fromRandom();
        await saveClientKeys?.call(PersistedClientKeys(
          clientId: _clientId!,
          rsaPublicKey: _keyPair!.publicKey.toString(),
          rsaPrivateKey: _keyPair!.privateKey.toString(),
        ));
      }
    }

    await publishPublicSigningKey();
    await _publishBundle();

    _republishTimer?.cancel();
    _republishTimer = Timer.periodic(bundleTtl ~/ 2, (_) async {
      try {
        await _publishBundle();
      } catch (e) {
        logger.warning('Failed to republish client key bundle: $e');
      }
    });
    return _myBundle!;
  }

  /// Cancels republishing and deletes this client's bundle from the
  /// atServer. The in-memory identity is retained, so a subsequent
  /// [registerClient] republishes under the same clientId.
  Future<void> deregisterClient() async {
    _republishTimer?.cancel();
    _republishTimer = null;
    if (_myBundle == null) {
      return;
    }
    _myBundle = null;
    await atClient.delete(
      AtKey.fromString(_bundleKeyUri),
      deleteRequestOptions: DeleteRequestOptions()..useRemoteAtServer = true,
    );
  }

  Future<void> _publishBundle() async {
    final bundle = ClientKeyBundle(
      clientId: clientId,
      enrollmentId: enrollmentId,
      createdAt: DateTime.now().toUtc(),
      keys: [
        BundleKey(
          use: SecretSharingAlgos.useEnc,
          alg: SecretSharingAlgos.rsa2048,
          pub: _keyPair!.publicKey.toString(),
        ),
      ],
    );
    final String signedJson = await wrapAndSignAndJsonEncode(bundle.toJson());
    final atKey = AtKey.fromString(_bundleKeyUri)
      ..metadata.ttl = bundleTtl.inMilliseconds;
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
    _myBundle = bundle;
    logger.info('Published client key bundle at $_bundleKeyUri');
  }

  /// Discovers the key bundles other clients of this atSign have published.
  ///
  /// Scans the atServer for hidden `__pqkb-` public keys (optionally
  /// restricted to [enrollmentId]), fetches each bundle, verifies its APKAM
  /// signature against the publishing enrollment's `_apsk` key, and checks
  /// that the enrollment named by the key's location matches the enrollment
  /// the bundle claims and was signed by. Bundles that fail any of these
  /// checks are logged and skipped. This client's own bundle is excluded.
  Future<List<ClientKeyBundle>> discoverClients({String? enrollmentId}) async {
    final atSign = atClient.getCurrentAtSign()!;
    final String regex = enrollmentId == null
        ? '__pqkb-.*\\.${EnrollmentConstants.perEnrollmentApproved}@'
        : '__pqkb-.*\\.$enrollmentId'
            '\\.${EnrollmentConstants.perEnrollmentApproved}@';
    final List<AtKey> bundleKeys = await atClient.getAtKeys(
      regex: regex,
      showHiddenKeys: true,
      useRemoteAtServer: true,
    );

    final bundles = <ClientKeyBundle>[];
    for (final bundleKey in bundleKeys) {
      try {
        final AtValue av = await atClient.get(
          bundleKey,
          getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
        );
        final envelope = jsonDecode(av.value as String) as Map;
        await verifyEnvelopeSignature(envelope, signerAtSign: atSign);
        final bundle = ClientKeyBundle.fromJson(envelope['payload']);

        if (bundle.clientId == _clientId) {
          continue; // our own bundle
        }
        // The enrollment that signed the envelope must be the enrollment the
        // bundle claims, and must own the namespace the bundle was found in:
        // key shape __pqkb-<clientId>.<enrollmentId>.a.__e
        final expectedKeyPart = '__pqkb-${bundle.clientId}'
            '.${bundle.enrollmentId}'
            '.${EnrollmentConstants.perEnrollmentApproved}';
        if (envelope['enrollmentId'] != bundle.enrollmentId ||
            '${bundleKey.key}.${bundleKey.namespace}' != expectedKeyPart) {
          logger.warning('Skipping bundle at $bundleKey: enrollment binding '
              'mismatch (bundle claims ${bundle.enrollmentId})');
          continue;
        }
        bundles.add(bundle);
      } catch (e) {
        logger.warning('Skipping bundle at $bundleKey: $e');
      }
    }
    return bundles;
  }
}
