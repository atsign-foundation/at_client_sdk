import 'dart:convert';
import 'dart:typed_data';

import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('PublishedNskeyKeyRing');

/// The at-key an nskey's public half is published under.
///
/// The **double** underscore is what makes eager publication both safe and
/// workable. Safe: an unauthenticated scan ignores `showhidden`, and a
/// `public:__` key is revealed only *by* `showhidden`, so an outsider cannot
/// enumerate which namespaces — which apps — an atSign uses, while `plookup`
/// still serves the key to anyone who knows the namespace. Workable: a *single*
/// underscore key is hidden from every scan but is written with **commit id -1**,
/// so it sits outside the commit log and sync can never push it.
AtKey nskeyAdvertisementKey(String owner, String namespace) => AtKey()
  ..key = '__nskey'
  ..namespace = namespace
  ..sharedBy = owner
  ..metadata = (Metadata()..isPublic = true);

/// Checks that a fetched advertisement really came from the atSign that claims
/// it, before anything is encapsulated to it.
///
/// The design requires every advertised encapsulation key to be an APKAM-signed
/// envelope verified against the publishing enrollment's `_apsk`, the same way
/// same-atSign and cross-atSign. That signing and verification is SS-2 / SS-1c.
abstract class AdvertisedKeyVerifier {
  /// Return the advertisement carried by [payload], or throw if it cannot be
  /// trusted as [owner]'s.
  Future<NskeyAdvertisement> verify(String owner, String payload);
}

/// Accepts advertisements **without checking any signature**.
///
/// This exists so the discovery and rotation mechanics can be exercised before
/// the signing work lands. It is not a trust decision anyone should ship: an
/// atServer operator, or anyone who can write the owner's public keys, can
/// substitute the key a sender encapsulates to. It shouts on every use so it
/// cannot pass unnoticed, and it is replaced wholesale when SS-1c lands.
class UnverifiedAdvertisedKeys implements AdvertisedKeyVerifier {
  @override
  Future<NskeyAdvertisement> verify(String owner, String payload) async {
    _logger.shout(
        'accepting the advertised nskey for $owner UNVERIFIED — no APKAM '
        'signature was checked, so the key encapsulated to is only as '
        'trustworthy as the server that served it (SS-1c)');
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return (
      nskeyKid: json['nskeyKid'] as String,
      publicKey: Uint8List.fromList(base64Decode(json['publicKey'] as String)),
    );
  }
}

/// An [NskeyKeyRing] that publishes the owner's nskey and discovers other
/// atSigns' by `plookup`.
///
/// Own privates are held in memory here; conveying them per-APKAM over the
/// secret-sharing substrate is SS-4's job, and when it lands it supplies them
/// instead of [mintAndPublish].
class PublishedNskeyKeyRing implements NskeyKeyRing {
  final AtClient _atClient;
  final AdvertisedKeyVerifier verifier;

  /// How long a fetched advertisement is trusted before it is re-fetched.
  ///
  /// This is the lever on how long a rotation can go unnoticed. A sender never
  /// sees a recipient's decapsulation fail, so re-fetching is the *only* way it
  /// learns the recipient rotated — and a sender still sealing to a superseded
  /// generation hands a revoked enrollment a key it can still open. Total
  /// exposure is this window plus one content-key lifetime.
  ///
  /// It is a window rather than a check per write because `ensureCurrent` runs
  /// on every `put`: fetching each time would put a round trip to the
  /// recipient's atServer on the write path and break offline writes.
  final Duration advertisementTtl;

  PublishedNskeyKeyRing(
    this._atClient, {
    AdvertisedKeyVerifier? verifier,
    this.advertisementTtl = const Duration(minutes: 15),
  }) : verifier = verifier ?? UnverifiedAdvertisedKeys();

  final Map<String, NskeyAdvertisement> _ownCurrent = {};
  final Map<String, Uint8List> _ownPrivates = {};
  final Map<String, ({NskeyAdvertisement advertisement, DateTime fetchedAt})>
      _remote = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _generation(String owner, String namespace, String kid) =>
      '${_scope(owner, namespace)}|$kid';

  /// Mint a generation for `(currentAtSign, namespace)` and publish its public
  /// half immediately.
  ///
  /// Called again for the same namespace this is a **rotation**: the new
  /// generation becomes current and the previous private is retained, so
  /// conveyances sealed to it still open.
  Future<NskeyAdvertisement> mintAndPublish(String namespace) async {
    final owner = _atClient.getCurrentAtSign()!;
    final pair = await XWingKeyPair.generate();
    final advertisement = (
      nskeyKid: nskeyKidOf(pair.publicKeyBytes),
      publicKey: pair.publicKeyBytes,
    );

    final advertisementKey = nskeyAdvertisementKey(owner, namespace);
    final payload = jsonEncode({
      'nskeyKid': advertisement.nskeyKid,
      'publicKey': base64Encode(advertisement.publicKey),
    });

    // Straight to the atServer first: an advertisement is only useful once a
    // *peer* can fetch it, and going through the local-first put would leave it
    // unpublished until the next sync.
    await _atClient.getRemoteSecondary()!.executeVerb(
        UpdateVerbBuilder()
          ..atKey = advertisementKey
          ..value = payload,
        sync: true);

    // …then locally, so the owner's own clients hold it across restarts without
    // a round trip. A `public:__` key carries a real commit id, so the two
    // converge rather than diverging.
    await _atClient.put(advertisementKey, payload);

    _ownCurrent[_scope(owner, namespace)] = advertisement;
    _ownPrivates[_generation(owner, namespace, advertisement.nskeyKid)] =
        pair.privateKeyBytes;
    return advertisement;
  }

  @override
  Future<NskeyAdvertisement?> currentPublic(
      String owner, String namespace) async {
    // The owner's own key never needs looking up — her clients hold it.
    if (owner == _atClient.getCurrentAtSign()) {
      return _ownCurrent[_scope(owner, namespace)];
    }

    final scope = _scope(owner, namespace);
    final cached = _remote[scope];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < advertisementTtl) {
      return cached.advertisement;
    }

    final String payload;
    try {
      final value =
          await _atClient.get(nskeyAdvertisementKey(owner, namespace));
      if (value.value == null) return cached?.advertisement;
      payload = value.value as String;
    } catch (_) {
      // No advertisement: under eager publication that means the recipient has
      // never used this namespace, which is the cold-start case. Keep any
      // previously-fetched one rather than losing a working key to a blip.
      return cached?.advertisement;
    }

    final advertisement = await verifier.verify(owner, payload);
    _remote[scope] = (advertisement: advertisement, fetchedAt: DateTime.now());
    return advertisement;
  }

  @override
  Future<Uint8List?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      _ownPrivates[_generation(owner, namespace, nskeyKid)];
}
