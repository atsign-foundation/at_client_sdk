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
/// Placement gives the canonical bundle its properties:
/// - only the owning enrollment can write into `<enrollmentId>.a.__e`, and
///   the bundle is additionally APKAM-signed (see [EnvelopeSigning]);
/// - hidden public keys (`public:__` prefix) are not enumerable by
///   unauthenticated scans or by other atSigns, but every authenticated
///   client of this atSign can discover them with `showHiddenKeys`,
///   regardless of its enrollment namespaces.
///
/// Additionally, for each application namespace passed to [registerClient],
/// the same signed bundle is published as a *namespace-scoped copy* — a
/// cleartext self key:
///
///     pqkb-<clientId>.<enrollmentId>.__pqkbns.<namespace>@atsign
///
/// The atServer's enrollment namespace authorization then enforces, with no
/// server changes:
/// - **write side**: only a connection with `rw` on `<namespace>` (or an
///   owner-class connection) can create the copy — so its presence proves
///   the publishing client can participate in that namespace;
/// - **read side**: only clients authorized for `<namespace>` can discover
///   it, so unrelated apps don't learn the roster.
///
/// The bundle's signed payload lists the namespaces it was registered under
/// ([ClientKeyBundle.namespaces]), so a genuine bundle *planted* by an
/// owner-class client under some other namespace is detected at discovery
/// time (location not in the signed list). [discoverClients] with a
/// `namespace` argument uses these copies, avoiding fetching and verifying
/// bundles of clients that could never receive an envelope in that
/// namespace anyway; copies are self keys, so they also sync to authorized
/// clients' local storage.
///
/// By default the identity is ephemeral: held in memory, published with
/// [bundleTtl], republished while this client runs, and gone when the
/// process ends. Apps that want a stable clientId across restarts supply
/// [loadClientKeys] / [saveClientKeys].
mixin PairwiseClientRegistration on ApkamSigning, EnvelopeSigning {
  /// Marker segment in namespace-scoped bundle copy key names.
  static const String namespaceScopedMarker = '__pqkbns';

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
  List<String> _registeredNamespaces = const [];

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
  /// [namespaces], when given, are the application namespaces this client
  /// participates in: a namespace-scoped copy of the bundle is published
  /// under each (see the mixin doc), and the list is included in the signed
  /// bundle payload. This client's enrollment must have `rw` access to each
  /// of them — the atServer refuses the copy otherwise.
  ///
  /// Also ensures this enrollment's APKAM public signing key is published
  /// ([ApkamSigning.publishPublicSigningKey]) so that other clients can
  /// verify the bundle's signature.
  ///
  /// Note: generating an RSA keypair in pure Dart takes on the order of a
  /// second; it happens at most once per [registerClient] call.
  Future<ClientKeyBundle> registerClient({Iterable<String>? namespaces}) async {
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
    _registeredNamespaces =
        namespaces == null ? const [] : (namespaces.toSet().toList()..sort());

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

  /// Cancels republishing and deletes this client's bundle — canonical and
  /// any namespace-scoped copies — from the atServer. The in-memory identity
  /// is retained, so a subsequent [registerClient] republishes under the
  /// same clientId.
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
    for (final ns in _registeredNamespaces) {
      try {
        await atClient.delete(
          _namespaceCopyKey(ns),
          deleteRequestOptions: DeleteRequestOptions()
            ..useRemoteAtServer = true,
        );
      } catch (e) {
        logger.warning('Failed to delete bundle copy in namespace $ns: $e');
      }
    }
  }

  AtKey _namespaceCopyKey(String ns) => AtKey()
    ..key = 'pqkb-$clientId.$enrollmentId.$namespaceScopedMarker'
    ..namespace = ns
    ..sharedBy = atClient.getCurrentAtSign();

  /// Publishes the canonical bundle and a copy per registered namespace.
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
      namespaces: _registeredNamespaces,
    );
    final String signedJson = await wrapAndSignAndJsonEncode(bundle.toJson());

    final atKey = AtKey.fromString(_bundleKeyUri)
      ..metadata.ttl = bundleTtl.inMilliseconds;
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
    logger.info('Published client key bundle at $_bundleKeyUri');

    for (final ns in _registeredNamespaces) {
      final copyKey = _namespaceCopyKey(ns)
        ..metadata.ttl = bundleTtl.inMilliseconds;
      // Cleartext self key (the bundle is public material, already inside a
      // signed envelope); raw JSON so pre-isEncrypted-fix readers fall back
      // to the raw value.
      await atClient.put(
        copyKey,
        signedJson,
        putRequestOptions: PutRequestOptions()
          ..useRemoteAtServer = true
          ..shouldEncrypt = false,
      );
      logger.info('Published bundle copy in namespace $ns');
    }
    _myBundle = bundle;
  }

  /// Discovers the key bundles other clients of this atSign have published.
  ///
  /// With no [namespace]: scans the atServer for hidden `__pqkb-` public
  /// keys (optionally restricted to [enrollmentId]) — every registered
  /// client of the atSign, regardless of namespaces.
  ///
  /// With a [namespace]: scans for the namespace-scoped bundle copies
  /// instead. This is the efficient form when you intend to share into a
  /// specific application namespace: only clients that registered for that
  /// namespace are returned (their enrollments provably hold `rw` on it —
  /// the atServer refuses the copy's write otherwise), and the server only
  /// reveals the copies to scanners authorized for that namespace.
  ///
  /// Every returned bundle has had its APKAM signature verified against the
  /// publishing enrollment's `_apsk` key, and its key location checked
  /// against the bundle's signed claims: clientId and enrollmentId must
  /// match the key name, and for namespace-scoped copies the location
  /// namespace must appear in the bundle's signed
  /// [ClientKeyBundle.namespaces] (so a genuine bundle planted under a
  /// foreign namespace by an owner-class client is rejected). Bundles that
  /// fail any check are logged and skipped. This client's own bundle is
  /// excluded.
  Future<List<ClientKeyBundle>> discoverClients(
      {String? enrollmentId, String? namespace}) async {
    final String eidPattern = enrollmentId ?? '[^.]+';
    final String regex = namespace == null
        ? '__pqkb-.*\\.$eidPattern'
            '\\.${EnrollmentConstants.perEnrollmentApproved}@'
        : 'pqkb-[^.]+\\.$eidPattern\\.$namespaceScopedMarker\\.$namespace@';
    final List<AtKey> bundleKeys = await atClient.getAtKeys(
      regex: regex,
      showHiddenKeys: namespace == null,
      useRemoteAtServer: true,
    );

    final bundles = <ClientKeyBundle>[];
    for (final bundleKey in bundleKeys) {
      final bundle = await _verifiedBundleAt(bundleKey, namespace: namespace);
      if (bundle != null && bundle.clientId != _clientId) {
        bundles.add(bundle);
      }
    }
    return bundles;
  }

  /// Fetches, signature-verifies and location-validates one bundle.
  /// Returns null (after logging) if any check fails.
  Future<ClientKeyBundle?> _verifiedBundleAt(AtKey bundleKey,
      {String? namespace}) async {
    try {
      final AtValue av = await atClient.get(
        bundleKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      final envelope = jsonDecode(av.value as String) as Map;
      await verifyEnvelopeSignature(envelope,
          signerAtSign: atClient.getCurrentAtSign()!);
      final bundle = ClientKeyBundle.fromJson(envelope['payload']);

      // The enrollment that signed the envelope must be the enrollment the
      // bundle claims...
      if (envelope['enrollmentId'] != bundle.enrollmentId) {
        logger.warning('Skipping bundle at $bundleKey: signer enrollment '
            'does not match bundle claim ${bundle.enrollmentId}');
        return null;
      }
      // ...and the key location must match the bundle's signed claims.
      final String keyString = bundleKey.toString();
      if (namespace == null) {
        // canonical: public:__pqkb-<clientId>.<enrollmentId>.a.__e@atsign
        final expected = 'public:__pqkb-${bundle.clientId}'
            '.${bundle.enrollmentId}'
            '.${EnrollmentConstants.perEnrollmentApproved}'
            '${atClient.getCurrentAtSign()}';
        if (keyString != expected) {
          logger.warning('Skipping bundle at $bundleKey: location does not '
              'match bundle claims (${bundle.clientId}, '
              '${bundle.enrollmentId})');
          return null;
        }
      } else {
        // copy: pqkb-<clientId>.<enrollmentId>.__pqkbns.<namespace>@atsign
        final expected = 'pqkb-${bundle.clientId}.${bundle.enrollmentId}'
            '.$namespaceScopedMarker.$namespace'
            '${atClient.getCurrentAtSign()}';
        if (keyString != expected) {
          logger.warning('Skipping bundle copy at $bundleKey: location does '
              'not match bundle claims (${bundle.clientId}, '
              '${bundle.enrollmentId})');
          return null;
        }
        // Planting protection: the signed payload must say the client
        // registered for the namespace this copy was found under.
        if (!bundle.namespaces.contains(namespace)) {
          logger.warning('Skipping bundle copy at $bundleKey: namespace '
              '$namespace is not in the bundle\'s signed namespace list '
              '${bundle.namespaces}');
          return null;
        }
      }
      return bundle;
    } catch (e) {
      logger.warning('Skipping bundle at $bundleKey: $e');
      return null;
    }
  }
}
