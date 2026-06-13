import 'dart:async' show Timer;
import 'dart:convert' show base64Decode, base64Encode, jsonDecode;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart' show XWingPureDartAlgo;
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
import 'package:at_client/src/secret_sharing/client_key_package.dart';
import 'package:meta/meta.dart' show experimental, protected;
import 'package:uuid/uuid.dart' show Uuid;

/// A client identity that an app chose to persist via
/// [PairwiseClientRegistration.saveClientKeys] /
/// [PairwiseClientRegistration.loadClientKeys].
///
/// [xWingSeed] is the base64 of the 32-byte X-Wing secret seed; the public
/// key is re-derived from it deterministically. Treat this as
/// device-local material — copying it to another device clones the client
/// identity.
@experimental
class PersistedClientKeys {
  final String clientId;
  final String xWingSeed;

  PersistedClientKeys({
    required this.clientId,
    required this.xWingSeed,
  });
}

/// Per-client registration for same-atSign secret sharing.
///
/// Each client generates a random [clientId] and a keypair, and publishes a
/// signed [ClientKeyPackage] as a *hidden public key* in its enrollment's
/// reserved namespace:
///
///     public:__sskb-<clientId>.<enrollmentId>.a.__e@atsign
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
///     sskb-<clientId>.<enrollmentId>.__sskbns.<namespace>@atsign
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
/// ([ClientKeyPackage.namespaces]), so a genuine bundle *planted* by an
/// owner-class client under some other namespace is detected at discovery
/// time (location not in the signed list). [discoverClients] with a
/// `namespace` argument uses these copies, avoiding fetching and verifying
/// bundles of clients that could never receive an envelope in that
/// namespace anyway; copies are self keys, so they also sync to authorized
/// clients' local storage.
///
/// By default the identity is ephemeral: held in memory, published with
/// [keyPackageTtl], republished while this client runs, and gone when the
/// process ends. Apps that want a stable clientId across restarts supply
/// [loadClientKeys] / [saveClientKeys].
@experimental
mixin PairwiseClientRegistration on ApkamSigning, EnvelopeSigning {
  /// Marker segment in namespace-scoped bundle copy key names.
  static const String namespaceScopedMarker = '__sskbns';

  /// How long a published bundle lives on the atServer. While registered,
  /// the bundle is republished at half this interval.
  Duration keyPackageTtl = Duration(hours: 24);

  /// Supply to give this client a stable identity across restarts.
  /// Called once, before generating a fresh identity; return null to
  /// generate fresh.
  Future<PersistedClientKeys?> Function()? loadClientKeys;

  /// Supply to persist a freshly generated identity (e.g. to the platform
  /// keystore / biometric storage — that is the app's concern).
  Future<void> Function(PersistedClientKeys keys)? saveClientKeys;

  String? _clientId;
  Uint8List? _xWingSeed;
  Uint8List? _xWingPublicKey;
  ClientKeyPackage? _myKeyPackage;
  Timer? _republishTimer;
  final Set<String> _registeredNamespaces = {};

  /// The application namespaces this client is currently registered under
  /// (the union of every [registerClient] call since the last
  /// [deregisterClient]).
  Set<String> get registeredNamespaces =>
      Set.unmodifiable(_registeredNamespaces);

  /// This client's random per-client id. Throws [StateError] until
  /// [registerClient] has completed.
  String get clientId {
    if (_clientId == null) {
      throw StateError('registerClient() has not been called');
    }
    return _clientId!;
  }

  bool get isRegistered => _myKeyPackage != null;

  /// The bundle this client most recently published.
  ClientKeyPackage? get myKeyPackage => _myKeyPackage;

  /// This client's X-Wing public key (1216 raw bytes), as published in its
  /// bundle. Throws [StateError] until [registerClient] has completed.
  Uint8List get xWingPublicKey {
    if (_xWingPublicKey == null) {
      throw StateError('registerClient() has not been called');
    }
    return _xWingPublicKey!;
  }

  /// This client's X-Wing secret seed (32 bytes) — for decapsulation by
  /// composing mixins, not for application use.
  @protected
  Uint8List get xWingSeed {
    if (_xWingSeed == null) {
      throw StateError('registerClient() has not been called');
    }
    return _xWingSeed!;
  }

  String get _keyPackageKeyUri => 'public:__sskb-$clientId.$enrollmentId'
      '.${EnrollmentConstants.perEnrollmentApproved}'
      '${atClient.getCurrentAtSign()}';

  /// Generates (or loads, via [loadClientKeys]) this client's identity,
  /// publishes its signed [ClientKeyPackage], and keeps republishing it at
  /// [keyPackageTtl] / 2 until [deregisterClient] is called.
  ///
  /// [namespaces], when given, are application namespaces this client
  /// participates in: a namespace-scoped copy of the bundle is published
  /// under each (see the mixin doc), and the list is included in the signed
  /// bundle payload. This client's enrollment must have `rw` access to each
  /// of them — the atServer refuses the copy otherwise.
  ///
  /// Namespaces are **additive across calls**: they union into
  /// [registeredNamespaces] (cleared by [deregisterClient]). This lets
  /// independent consumers of a shared instance — the app and SDK-internal
  /// users such as crypto providers — each declare their namespaces without
  /// clobbering the other's registrations.
  ///
  /// Also ensures this enrollment's APKAM public signing key is published
  /// ([ApkamSigning.publishPublicSigningKey]) so that other clients can
  /// verify the bundle's signature.
  Future<ClientKeyPackage> registerClient(
      {Iterable<String>? namespaces}) async {
    if (_clientId == null) {
      final loaded = await loadClientKeys?.call();
      if (loaded != null) {
        _clientId = loaded.clientId;
        _xWingSeed = base64Decode(loaded.xWingSeed);
        // the public key derives deterministically from the seed
        final kp = await XWingPureDartAlgo.instance.generateKeyPair(_xWingSeed);
        _xWingPublicKey = kp.publicKey;
      } else {
        _clientId = Uuid().v4();
        final kp = await XWingPureDartAlgo.instance.generateKeyPair();
        _xWingSeed = kp.secretKey;
        _xWingPublicKey = kp.publicKey;
        await saveClientKeys?.call(PersistedClientKeys(
          clientId: _clientId!,
          xWingSeed: base64Encode(_xWingSeed!),
        ));
      }
    }
    if (namespaces != null) {
      _registeredNamespaces.addAll(namespaces);
    }

    await publishPublicSigningKey();
    await _publishKeyPackage();

    _republishTimer?.cancel();
    _republishTimer = Timer.periodic(keyPackageTtl ~/ 2, (_) async {
      try {
        await _publishKeyPackage();
      } catch (e) {
        logger.warning('Failed to republish client key bundle: $e');
      }
    });
    return _myKeyPackage!;
  }

  /// Cancels republishing and deletes this client's bundle — canonical and
  /// any namespace-scoped copies — from the atServer, clearing
  /// [registeredNamespaces]. The in-memory identity is retained, so a
  /// subsequent [registerClient] republishes under the same clientId.
  Future<void> deregisterClient() async {
    _republishTimer?.cancel();
    _republishTimer = null;
    if (_myKeyPackage == null) {
      return;
    }
    _myKeyPackage = null;
    await atClient.delete(
      AtKey.fromString(_keyPackageKeyUri),
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
    _registeredNamespaces.clear();
  }

  AtKey _namespaceCopyKey(String ns) => AtKey()
    ..key = 'sskb-$clientId.$enrollmentId.$namespaceScopedMarker'
    ..namespace = ns
    ..sharedBy = atClient.getCurrentAtSign();

  /// Publishes the canonical bundle and a copy per registered namespace.
  Future<void> _publishKeyPackage() async {
    final bundle = ClientKeyPackage(
      clientId: clientId,
      enrollmentId: enrollmentId,
      createdAt: DateTime.now().toUtc(),
      keys: [
        PackageKey(
          use: SecretSharingAlgos.useEnc,
          alg: SecretSharingAlgos.xWing,
          pub: base64Encode(_xWingPublicKey!),
        ),
      ],
      namespaces: _registeredNamespaces.toList()..sort(),
    );
    final String signedJson = await wrapAndSignAndJsonEncode(bundle.toJson());

    final atKey = AtKey.fromString(_keyPackageKeyUri)
      ..metadata.ttl = keyPackageTtl.inMilliseconds;
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
    logger.info('Published client key bundle at $_keyPackageKeyUri');

    for (final ns in _registeredNamespaces) {
      final copyKey = _namespaceCopyKey(ns)
        ..metadata.ttl = keyPackageTtl.inMilliseconds;
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
    _myKeyPackage = bundle;
  }

  /// Discovers the key bundles other clients of this atSign have published.
  ///
  /// With no [namespace]: scans the atServer for hidden `__sskb-` public
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
  /// [ClientKeyPackage.namespaces] (so a genuine bundle planted under a
  /// foreign namespace by an owner-class client is rejected). Bundles that
  /// fail any check are logged and skipped. This client's own bundle is
  /// excluded.
  /// [excludeEnrollmentIds] drops any package published by one of those
  /// enrollments. Primary use is revocation: a revoked enrollment's key
  /// packages stay published until their TTL expires, so a key holder
  /// rotating after a revocation must explicitly skip them — otherwise the
  /// new epoch key would be encapsulated straight back to the evicted
  /// client.
  Future<List<ClientKeyPackage>> discoverClients(
      {String? enrollmentId,
      String? namespace,
      Set<String>? excludeEnrollmentIds}) async {
    final String eidPattern = enrollmentId ?? '[^.]+';
    final String regex = namespace == null
        ? '__sskb-.*\\.$eidPattern'
            '\\.${EnrollmentConstants.perEnrollmentApproved}@'
        : 'sskb-[^.]+\\.$eidPattern\\.$namespaceScopedMarker\\.$namespace@';
    final List<AtKey> bundleKeys = await atClient.getAtKeys(
      regex: regex,
      showHiddenKeys: namespace == null,
      useRemoteAtServer: true,
    );

    final bundles = <ClientKeyPackage>[];
    for (final bundleKey in bundleKeys) {
      final bundle =
          await _verifiedKeyPackageAt(bundleKey, namespace: namespace);
      if (bundle != null &&
          bundle.clientId != _clientId &&
          !(excludeEnrollmentIds?.contains(bundle.enrollmentId) ?? false)) {
        bundles.add(bundle);
      }
    }
    return bundles;
  }

  /// Fetches, signature-verifies and location-validates one bundle.
  /// Returns null (after logging) if any check fails.
  Future<ClientKeyPackage?> _verifiedKeyPackageAt(AtKey bundleKey,
      {String? namespace}) async {
    try {
      final AtValue av = await atClient.get(
        bundleKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      final envelope = jsonDecode(av.value as String) as Map;
      await verifyEnvelopeSignature(envelope,
          signerAtSign: atClient.getCurrentAtSign()!);
      final bundle = ClientKeyPackage.fromJson(envelope['payload']);

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
        // canonical: public:__sskb-<clientId>.<enrollmentId>.a.__e@atsign
        final expected = 'public:__sskb-${bundle.clientId}'
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
        // copy: sskb-<clientId>.<enrollmentId>.__sskbns.<namespace>@atsign
        final expected = 'sskb-${bundle.clientId}.${bundle.enrollmentId}'
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
