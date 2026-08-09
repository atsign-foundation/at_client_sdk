import 'dart:typed_data';

import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:crypto/crypto.dart' show sha256;

/// A published nskey generation: the public half, the kid naming it, and the
/// key-establishment algorithm it is a key for.
///
/// [alg] is an id from [SecretSharingAlgos.keyAlgos]. It is not decorative: a
/// sender cannot tell an X-Wing encapsulation key from an ML-KEM one by
/// looking — they are both opaque byte strings — and encapsulating under the
/// wrong KEM produces a conveyance the owner can never open.
typedef NskeyAdvertisement = ({
  String nskeyKid,
  Uint8List publicKey,
  String alg,
  List<String> suites,
});

/// What an advertisement carrying no `suites` field is taken to support.
///
/// Exactly the one construction that existed when such advertisements were
/// written. It must never grow: adding to it would claim, on behalf of owners
/// that never said so, that they can open something they cannot — and unlike a
/// key package, an advertisement is fetched by *senders*, who act on the claim
/// immediately.
const List<String> legacyNskeySuites = [SecretSharingAlgos.xWingHpke];

/// The id of an nskey generation — a SHA-256 prefix of its public half, so it is
/// derivable by anyone holding the key and identical for every party that uses it.
String nskeyKidOf(Uint8List publicKey) =>
    sha256.convert(publicKey).toString().substring(0, 16);

/// Where the `at/nskey` provider gets namespace key material.
///
/// Per `(atSign, namespace)` there is exactly **one live** nskey keypair,
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

  /// The **decapsulation key** this client holds for a *named generation* of
  /// `(owner, namespace)` — what `pqOpen` takes, ready to use.
  ///
  /// Not the persisted seed. The two are the same bytes for X-Wing but not for
  /// ML-KEM, whose decapsulation key is expanded from its seed, so an
  /// implementation that stores seeds expands here rather than making every
  /// caller know which it holds.
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
/// Test scaffolding: every consumer is a test that wants the data path
/// exercised without minting, publication or conveyance. The production ring
/// is `PublishedNskeyKeyRing`, which does all three for real.
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
    String keyAlgo = SecretSharingAlgos.xWing,
  }) {
    final kid =
        seedPublicOnly(owner, namespace,
            publicKey: publicKey, keyAlgo: keyAlgo);
    _private[_generation(owner, namespace, kid)] = privateKey;
    return kid;
  }

  /// Seed only the public half — a sender who can encapsulate to a recipient but
  /// cannot decapsulate, which is every cross-atSign sender.
  String seedPublicOnly(
    String owner,
    String namespace, {
    required Uint8List publicKey,
    String keyAlgo = SecretSharingAlgos.xWing,
  }) {
    final kid = nskeyKidOf(publicKey);
    _current[_scope(owner, namespace)] = (
      nskeyKid: kid,
      publicKey: publicKey,
      alg: keyAlgo,
      suites: SecretSharingAlgos.openableSuitesFor(keyAlgo),
    );
    return kid;
  }

  /// Drop the current generation for `(owner, namespace)` without touching the
  /// privates — what a ring looks like once an advertisement has aged out.
  void forget(String owner, String namespace) =>
      _current.remove(_scope(owner, namespace));

  @override
  Future<NskeyAdvertisement?> currentPublic(
          String owner, String namespace) async =>
      _current[_scope(owner, namespace)];

  @override
  Future<Uint8List?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      _private[_generation(owner, namespace, nskeyKid)];
}
