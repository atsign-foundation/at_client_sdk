import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

/// A published nskey generation: the public half and the kid naming it.
typedef NskeyAdvertisement = ({String nskeyKid, Uint8List publicKey});

/// The id of an nskey generation — a SHA-256 prefix of its public half, so it is
/// derivable by anyone holding the key and identical for every party that uses it.
String nskeyKidOf(Uint8List publicKey) =>
    sha256.convert(publicKey).toString().substring(0, 16);

/// Where the `at/nskey` provider gets namespace key material.
///
/// Per `(atSign, namespace)` there is exactly **one live** X-Wing nskey keypair,
/// published at `public:__nskey.<ns>@<owner>` from the moment it is minted. It is
/// the recipient key for both directions: the owner encapsulates her own CKs to it
/// for self data, and external senders encapsulate CKs to it when sharing with her.
/// The private half decapsulates CKs — it never decrypts application data.
///
/// Rotation replaces the live generation but does not retire the old private:
/// conveyances written before it are still sealed to that one, so a ring keeps
/// every generation it has held, named by `nskeyKid`. Sealing always uses
/// [currentPublic]; opening uses the generation the record names.
///
/// The `owner` argument is the **nskey owner** — `sharedWith ?? sharedBy` on the
/// record, which on an inbound conveyance is the *recipient*, not the sender that
/// owns the record.
abstract class NskeyKeyRing {
  /// The generation new conveyances seal to for `(owner, namespace)`.
  ///
  /// For self data this is the owner's own; for a share it is the recipient's,
  /// fetched from `public:__nskey.<ns>@<recipient>` via `plookup` and verified
  /// against the publisher's `_apsk`.
  ///
  /// Null when the namespace has no nskey at all, which under eager publication
  /// means exactly one thing: that atSign has never used the namespace. There is
  /// no atSign-level key to fall back to — `public:pq_signing_root@<atSign>` is
  /// a signing root and cannot receive an encapsulation — so the caller has no
  /// post-quantum target and the write fails unless legacy is opted into.
  Future<NskeyAdvertisement?> currentPublic(String owner, String namespace);

  /// The private half this client holds for a *named generation* of
  /// `(owner, namespace)`.
  ///
  /// Null when this client is not authorised for the namespace, or has not yet
  /// received that generation. Holding none at all leaves the value undecryptable
  /// rather than silently skipped; missing only an older one is recoverable by
  /// pulling that generation over the substrate.
  Future<Uint8List?> privateHalf(
      String owner, String namespace, String nskeyKid);
}

/// An in-memory [NskeyKeyRing] seeded directly with keypairs.
///
/// This exists so the data path can be exercised end-to-end before the substrate
/// delivers privates for real — it inverts the dependency order for demonstration
/// only. The production path is unchanged: when nskey minting and per-APKAM
/// conveyance land, they supply a real [NskeyKeyRing] and this becomes test-only
/// scaffolding.
class InMemoryNskeyKeyRing implements NskeyKeyRing {
  final Map<String, NskeyAdvertisement> _current = {};
  final Map<String, Uint8List> _private = {};

  static String _scope(String owner, String namespace) => '$owner|$namespace';

  static String _generation(String owner, String namespace, String nskeyKid) =>
      '${_scope(owner, namespace)}|$nskeyKid';

  /// Seed both halves for `(owner, namespace)` and make them current — the state a
  /// client is in once it holds the namespace key. Returns the generation's kid.
  ///
  /// Seeding again with a different keypair models a rotation: the new generation
  /// becomes current and the earlier private is retained, so records sealed to it
  /// still open.
  String seedKeypair(
    String owner,
    String namespace, {
    required Uint8List publicKey,
    required Uint8List privateKey,
  }) {
    final kid = seedPublicOnly(owner, namespace, publicKey: publicKey);
    _private[_generation(owner, namespace, kid)] = privateKey;
    return kid;
  }

  /// Seed only the public half — a sender who can encapsulate to a recipient but
  /// cannot decapsulate, which is every cross-atSign sender.
  String seedPublicOnly(
    String owner,
    String namespace, {
    required Uint8List publicKey,
  }) {
    final kid = nskeyKidOf(publicKey);
    _current[_scope(owner, namespace)] = (nskeyKid: kid, publicKey: publicKey);
    return kid;
  }

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      _current[_scope(owner, namespace)];

  @override
  Future<Uint8List?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      _private[_generation(owner, namespace, nskeyKid)];
}
