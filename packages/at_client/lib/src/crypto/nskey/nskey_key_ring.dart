import 'dart:typed_data';

import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_client/src/secret_sharing/key_package.dart' show PackageKey;
import 'package:at_auth/at_auth.dart' show publicKeyKid;

/// The version stamped on the nskey advertisement payload.
///
/// Required on the way in: a reader that treats an absent version as "the
/// oldest shape I know" is guessing on the writer's behalf about the meaning
/// of every field after it.
const int nskeyAdvertisementVersion = 1;

/// The encapsulation key(s) an atSign advertises for a namespace at
/// `public:__nskey.<ns>@<owner>`.
///
/// Spelled as a key package is — `{v, createdAt, keys:[…], suites}` with
/// `{use, alg, pub, kid}` entries — so that one vocabulary covers every "list
/// of keys with algorithms" in the protocol.
///
/// An entry's `alg` is an id from [SecretSharingAlgos.keyAlgos] and is not
/// decorative: a sender cannot tell an X-Wing encapsulation key from an ML-KEM
/// one by looking — they are both opaque byte strings — and encapsulating under
/// the wrong KEM produces a conveyance the owner can never open.
class NskeyAdvertisement {
  final int v;
  final DateTime createdAt;
  final List<PackageKey> keys;

  /// The sealing suites this generation's owner can **open**, strongest first.
  ///
  /// Derived from [keys] when the caller does not state it, never from the
  /// build's own supported list: what this owner can open is fixed by the keys
  /// it actually advertises, not by what this client happens to implement.
  final List<String> suites;

  factory NskeyAdvertisement({
    required int v,
    required DateTime createdAt,
    required List<PackageKey> keys,
    List<String>? suites,
  }) =>
      NskeyAdvertisement._(
        v: v,
        createdAt: createdAt,
        keys: keys,
        suites: suites ??
            SecretSharingAlgos.openableSuitesForAll(keys.map((k) => k.alg)),
      );

  NskeyAdvertisement._({
    required this.v,
    required this.createdAt,
    required this.keys,
    required this.suites,
  });

  /// An advertisement carrying one encapsulation key, built from raw material.
  factory NskeyAdvertisement.single({
    required Uint8List publicKey,
    required String alg,
    DateTime? createdAt,
    List<String>? suites,
    int v = nskeyAdvertisementVersion,
  }) =>
      NskeyAdvertisement(
        v: v,
        createdAt: createdAt ?? DateTime.now().toUtc(),
        keys: [
          PackageKey.fromBytes(
              use: SecretSharingAlgos.useEnc, alg: alg, pub: publicKey),
        ],
        suites: suites,
      );

  /// The payload an advertisement is published as — the inner document, before
  /// it is wrapped in its APKAM-signed envelope.
  Map<String, Object?> toPayload() => {
        'v': v,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'keys': keys.map((k) => k.toJson()).toList(),
        'suites': suites,
      };

  /// Reads a published advertisement payload.
  ///
  /// Structural only — it says whether the document is an advertisement, not
  /// whether it can be trusted or whether this build can encapsulate to what it
  /// names. The trust check is the caller's (`AdvertisedKeyVerifier`), and so is
  /// the capability check.
  ///
  /// Malformed entries inside `keys` are skipped rather than fatal, since a
  /// newer writer may advertise entries spelled with fields this version does
  /// not know. An advertisement left with **no** usable entry is fatal, because
  /// there is then nothing to seal to.
  ///
  /// Throws [FormatException], whose message names the specific defect so a
  /// caller can prefix it with whose advertisement it was.
  static NskeyAdvertisement fromPayload(Object? payload) {
    if (payload is! Map) {
      throw FormatException('is not an advertisement document');
    }
    final v = payload['v'];
    if (v != nskeyAdvertisementVersion) {
      throw FormatException(
          'declares payload version $v, which this build has no code for — '
          'refusing rather than reading it as version '
          '$nskeyAdvertisementVersion');
    }
    final createdAt = payload['createdAt'];
    if (createdAt is! String) {
      throw FormatException('carries no mint time');
    }
    final rawKeys = payload['keys'];
    if (rawKeys is! List) {
      throw FormatException(
          'advertises no keys, so there is nothing to seal to');
    }
    final keys =
        rawKeys.map(PackageKey.fromJson).whereType<PackageKey>().toList();
    if (keys.isEmpty) {
      throw FormatException(
          'advertises no key entry this build can read, so there is nothing to '
          'seal to');
    }
    // NOTE: suite names this build does not know are kept — the list is the
    // OWNER's statement about what it can open, not this build's.
    final suites = payload['suites'];
    if (suites is! List) {
      throw FormatException(
          'declares no suites, so there is nothing it can be sealed under');
    }
    return NskeyAdvertisement(
      v: v,
      createdAt: DateTime.parse(createdAt),
      keys: keys,
      suites: suites.whereType<String>().toList(),
    );
  }

  /// The first **active** key in [supportedAlgos] order (strongest first) this
  /// advertisement offers for [use], or null when there is no algorithm in
  /// common and when every one they share is retired.
  PackageKey? bestKeyFor(List<String> supportedAlgos,
      {String use = SecretSharingAlgos.useEnc}) {
    for (final alg in supportedAlgos) {
      for (final key in keys) {
        if (key.alg == alg && key.use == use && key.offeredForNewOperations) {
          return key;
        }
      }
    }
    return null;
  }

  /// The entry a sender willing to seal under [sealsTo] should encapsulate to:
  /// the first of those algorithms this advertisement offers.
  ///
  /// [sealsTo] is strongest-first, so an owner offering both gets sealed to
  /// under the better one without either side negotiating. Null when the owner
  /// offers nothing on that list — which for a *narrowed*
  /// `AtClientPreference.sealsToKeyAlgorithms` is the deployment's own refusal
  /// arriving, not a broken advertisement.
  PackageKey? usableFor(List<String> sealsTo) => bestKeyFor(sealsTo);

  /// The entry this advertisement carries under [kid], or null if it carries
  /// none.
  ///
  /// What a party holding a *kid* must ask, and the counterpart of [usableFor]
  /// for a party holding an *algorithm*. [nskeyKid] and [publicKey] answer for
  /// the one entry a sender with no preference would pick, so on an
  /// advertisement carrying two they are silently wrong about the other.
  PackageKey? entryWithKid(String kid) {
    for (final key in keys) {
      if (key.kid == kid) return key;
    }
    return null;
  }

  /// [usableFor] over everything this build can encapsulate to — the answer the
  /// getters below give. A *sender* asks [usableFor] with its own list instead.
  PackageKey get _usable =>
      usableFor(SecretSharingAlgos.keyAlgos) ??
      (throw StateError(
          'this advertisement offers no key this build can encapsulate to. A '
          'verified advertisement always offers one, so this came from '
          'somewhere other than the reader'));

  /// The kid of the entry a sender with no algorithm preference seals to.
  String get nskeyKid => _usable.kid;

  /// The public half of the entry a sender with no preference seals to — not
  /// "the" key, since an advertisement may carry one entry per algorithm.
  Uint8List get publicKey => _usable.pubBytes;

  /// The algorithm of the entry a sender with no preference seals to; one with
  /// a preference asks [usableFor].
  String get alg => _usable.alg;
}

/// The id of an nskey generation — a SHA-256 prefix of its public half, so it
/// is derivable by anyone holding the key and identical for every party that
/// uses it.
///
/// An alias for at_auth's [publicKeyKid], the ONE derivation every record that
/// advertises keys uses — a second one that disagreed about the preimage would
/// strand every generation named under it.
String nskeyKidOf(Uint8List publicKey) => publicKeyKid(publicKey);

/// An nskey generation's **seed**: the compact form the whole keypair
/// re-derives from — the ONLY form that may be filed durably or conveyed
/// to another enrollment.
///
/// Distinct from [NskeyDecapsulationKey] at the type level because the two
/// are the same bytes for X-Wing and NOT for ML-KEM, whose decapsulation
/// key is expanded and cannot be turned back into a public half. Filing or
/// conveying the expanded form strands the generation after a restart — every
/// record sealed to it becomes permanently unopenable — and the type makes
/// that a compile error instead.
extension type const NskeySeed(Uint8List bytes) {}

/// An nskey generation's **decapsulation key**: the expanded form `pqOpen`
/// opens conveyances with — derived from an [NskeySeed], held in memory,
/// never filed and never conveyed.
extension type const NskeyDecapsulationKey(Uint8List bytes) {}

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

  /// The [NskeyDecapsulationKey] this client holds for a *named generation*
  /// of `(owner, namespace)` — what `pqOpen` takes, ready to use.
  ///
  /// Not the persisted [NskeySeed] — see the two types for why the
  /// distinction is critical. An implementation that stores seeds
  /// expands here rather than making every caller know which it holds.
  ///
  /// Null when this client is not authorised for the namespace, or has not yet
  /// received that generation. Holding none at all leaves the value undecryptable
  /// rather than silently skipped; missing only an older one is recoverable by
  /// pulling that generation over the substrate.
  Future<NskeyDecapsulationKey?> privateHalf(
      String owner, String namespace, String nskeyKid);
}

/// An in-memory [NskeyKeyRing] seeded directly with keypairs.
///
/// Test scaffolding: it exercises the data path without minting, publication
/// or conveyance. The production ring is `PublishedNskeyKeyRing`, which does
/// all three for real.
class InMemoryNskeyKeyRing implements NskeyKeyRing {
  final Map<String, NskeyAdvertisement> _current = {};
  final Map<String, NskeyDecapsulationKey> _private = {};

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
    final kid = seedPublicOnly(owner, namespace,
        publicKey: publicKey, keyAlgo: keyAlgo);
    _private[_generation(owner, namespace, kid)] =
        NskeyDecapsulationKey(privateKey);
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
    final advertisement = NskeyAdvertisement.single(
      publicKey: publicKey,
      alg: keyAlgo,
      suites: SecretSharingAlgos.openableSuitesFor(keyAlgo),
    );
    _current[_scope(owner, namespace)] = advertisement;
    return advertisement.nskeyKid;
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
  Future<NskeyDecapsulationKey?> privateHalf(
          String owner, String namespace, String nskeyKid) async =>
      _private[_generation(owner, namespace, nskeyKid)];
}
