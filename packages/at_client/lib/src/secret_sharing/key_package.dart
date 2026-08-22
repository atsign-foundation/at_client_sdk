import 'dart:convert' show base64Decode, base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart' show KeyEntryStatus, publicKeyKidOfBase64;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:meta/meta.dart' show experimental;

/// Re-exported so that the three records advertising keys name one type for
/// one field. It lives in at_auth because at_auth is the lower package and the
/// `_apsk` advertisement composed there carries the same `status` — the same
/// reason `publicKeyKid` lives there rather than here.
export 'package:at_auth/at_auth.dart' show KeyEntryStatus;

/// One public key advertised in a [KeyPackage].
///
/// [kid] is a short identifier for the key (a SHA-256 prefix of [pub]) which
/// envelopes use to say which of the recipient's keys was used. [alg] is an
/// algorithm id from [SecretSharingAlgos]; readers skip entries whose [alg]
/// or [use] they do not recognise, which is what lets a key package advertise
/// new suites without breaking old readers.
@experimental
class PackageKey {
  final String kid;
  final String use;
  final String alg;
  final String pub;

  /// Whether this key is still offered for new operations — an open token,
  /// see [KeyEntryStatus].
  ///
  /// Ask [offeredForNewOperations] rather than comparing the token: that is
  /// the decision this field exists for on the sender's side, and it answers
  /// correctly for a token this build has never heard of.
  final String status;

  PackageKey({
    required this.use,
    required this.alg,
    required this.pub,
    String? kid,
    this.status = KeyEntryStatus.active,
  }) : kid = kid ?? computeKid(pub);

  /// A key held as raw material rather than as the base64 an advertisement
  /// carries — what a freshly minted KEM keypair hands back.
  ///
  /// The [kid] this derives is identical to [publicKeyKid] over the same bytes,
  /// because [computeKid] decodes before hashing; a caller that has bytes and a
  /// caller that has text arrive at the same id.
  PackageKey.fromBytes({
    required String use,
    required String alg,
    required Uint8List pub,
    String status = KeyEntryStatus.active,
  }) : this(use: use, alg: alg, pub: base64Encode(pub), status: status);

  /// The key material [pub] encodes.
  ///
  /// Every consumer that hands the key to a KEM wants the material — an
  /// encapsulation is over bytes — while the wire carries base64. Decoding once
  /// here rather than at each call site is the same reasoning that puts
  /// [publicKeyKidOfBase64] beside `publicKeyKid`: a key decoded in two places
  /// is a key that can be decoded two ways.
  late final Uint8List pubBytes = base64Decode(pub);

  /// First 8 bytes, hex-encoded, of the SHA-256 of the public key material,
  /// for a [pub] held as base64 — which is how a key package carries one.
  ///
  /// Delegates to at_auth's [publicKeyKidOfBase64], the one derivation in the
  /// tree: the `_apsk` advertisement, a key package and an nskey
  /// advertisement all spell an entry the same way, and a kid computed two
  /// ways is a verification failure with nothing to say for itself — both
  /// sides compile, and the mismatch surfaces only as an envelope that will
  /// not verify, or a sender sealing to a kid nobody listens on.
  static String computeKid(String pub) => publicKeyKidOfBase64(pub);

  /// Whether a sender may seal to this key — see
  /// [KeyEntryStatus.offersNewOperations]. A holder deciding whether it can
  /// **open** an envelope already addressed here does not ask: a retired key
  /// is retained precisely so that it still opens what was sealed to it.
  bool get offeredForNewOperations =>
      KeyEntryStatus.offersNewOperations(status);

  /// `status` is emitted for any key that is not active and omitted for one
  /// that is, because absent already means [KeyEntryStatus.active] and every
  /// record written before rotation existed says it that way. Emitting the
  /// default on every entry would move the bytes of every advertisement in the
  /// protocol to state what their absence already states. Whatever token is
  /// emitted is the one that was read: an older build republishing a record
  /// must not weaken what its owner said about a key.
  Map<String, Object?> toJson() => {
        'kid': kid,
        'use': use,
        'alg': alg,
        'pub': pub,
        if (status != KeyEntryStatus.active) 'status': status,
      };

  static PackageKey? fromJson(Object? json) {
    if (json is! Map) return null;
    final kid = json['kid'];
    final use = json['use'];
    final alg = json['alg'];
    final pub = json['pub'];
    if (kid is! String || use is! String || alg is! String || pub is! String) {
      return null;
    }
    return PackageKey(
      kid: kid,
      use: use,
      alg: alg,
      pub: pub,
      status: KeyEntryStatus.fromWire(json['status']),
    );
  }
}

/// The KEM recipient key(s) one **APKAM keypair** advertises so that other
/// clients of the same atSign can seal secrets to it.
///
/// The recipient unit is the APKAM keypair, not a client process. Enrollment
/// cardinality is **1:1:1** — one enrollment has exactly one APKAM keypair and
/// therefore exactly one key package — so a key package is identified by its
/// [enrollmentId] (with [apkamId] carried alongside for reference).
///
/// Key packages are **enrollment-internal** — they live in the enrollment
/// record, conveyed there by riding `enroll:request` as opaque
/// `EnrollParams.metadata` at enrollment time, and are discovered only via the
/// gated `enroll:listns` verb (see [EnrollmentDirectory]). They are **not**
/// published as ordinary at-keys. Per the ratified design the advertised key
/// package is wrapped in an APKAM-signed envelope by its generating enrollment
/// and verified against that enrollment's `_apsk`, so the encapsulation target
/// is authenticated rather than merely server-vouched. The signed form is
/// produced by `KeyPackageRegistration.signedKeyPackagePayload` and checked by
/// [VerbEnrollmentDirectory]; a package that does not verify, or that is signed
/// by an enrollment other than the one advertising it, is not sealed to.
///
/// [toJson] / [fromPayload] are the **inner** payload — the value stored at
/// `metadata.keyPackage` is that payload wrapped in the signed envelope.
/// [enrollmentId] and [apkamId] are carried by the enclosing verb structure,
/// not duplicated in the payload.
@experimental
class KeyPackage {
  static const int currentVersion = 1;

  final int v;

  /// The enrollment this key package belongs to.
  final String enrollmentId;

  /// The APKAM keypair this key package belongs to, as reported by the verb
  /// (the enrollment's `apkamPubKey`). Null on a key package this client builds
  /// for its own enrollment — identity is carried by the enclosing enrollment.
  final String? apkamId;

  final DateTime createdAt;
  final List<PackageKey> keys;

  /// The sealing suites this package's holder can **open**, strongest first.
  ///
  /// `keys[].alg` says which KEM key a sender encapsulates to; it does not say
  /// which envelope construction the holder can unwrap. Without this a sender
  /// has no way to discover that, so it stamps the one suite it knows and a
  /// second suite can only be introduced by upgrading every reader first —
  /// release-ordering agility rather than negotiated agility.
  ///
  /// Required. It was once optional, with an absent field meaning "the one
  /// suite that existed when this was written" — a hatch for a predecessor
  /// that never shipped, and one that quietly spoke for holders who had said
  /// nothing.
  ///
  /// Derived from [keys] when the caller does not state it, never from the
  /// build's own [SecretSharingAlgos.suites]. That list is what this client can
  /// *produce and open given the right key*; what this package's holder can
  /// open is fixed by the keys it actually advertises. Defaulting to the former
  /// made a package advertising one KEM claim it could unwrap constructions
  /// built on the other.
  final List<String> suites;

  /// [suites] defaults to what [keys] can open — see the field's own doc for
  /// why that is not the same as what this build supports.
  factory KeyPackage({
    required String enrollmentId,
    String? apkamId,
    required DateTime createdAt,
    required List<PackageKey> keys,
    List<String>? suites,
    int v = currentVersion,
  }) =>
      KeyPackage._(
        enrollmentId: enrollmentId,
        apkamId: apkamId,
        createdAt: createdAt,
        keys: keys,
        suites: suites ??
            SecretSharingAlgos.openableSuitesForAll(keys.map((k) => k.alg)),
        v: v,
      );

  KeyPackage._({
    required this.enrollmentId,
    required this.apkamId,
    required this.createdAt,
    required this.keys,
    required this.suites,
    required this.v,
  });

  /// The first suite in [senderSuites] order (strongest first) that this
  /// package's holder can also open, or null if there is no overlap.
  ///
  /// A sender with no overlap must not fall back to stamping its own
  /// preference: the holder would receive an envelope it cannot unwrap, and
  /// the failure would arrive as an opaque AEAD error on the far side.
  String? bestSuiteFor(List<String> senderSuites) =>
      SecretSharingAlgos.bestSuiteBetween(senderSuites, suites);

  /// The addressing token for this key package: the [kid] of its **active**
  /// enc-use key (the KEM public key a sender seals to). Null if the package
  /// advertises no active key for [SecretSharingAlgos.keyAlgos].
  ///
  /// A package that has rotated advertises the superseded key as well, so that
  /// envelopes still in flight to it can be opened; this is the address senders
  /// use from now on, which is the new one.
  String? get kpid => bestKeyFor(SecretSharingAlgos.keyAlgos)?.kid;

  /// The first **active** key in [supportedAlgos] order (strongest first) that
  /// this key package advertises for [use]. Returns null if the package and
  /// [supportedAlgos] have no algorithm in common, or if every key they do have
  /// in common is retired.
  ///
  /// Retired entries are skipped because this answers "which key should be used
  /// now" for a sender, and a retired key is retained for opening what was
  /// already sealed to it rather than for receiving anything more — see
  /// [KeyEntryStatus]. A holder deciding whether it can open a given envelope
  /// asks [keys] instead, which carries retired entries too.
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

  /// The value stored at `metadata.keyPackage` — the payload
  /// only. [enrollmentId] / [apkamId] are carried by the enclosing verb
  /// structure (the enrollment and its APKAM-keypair entry), not repeated here.
  Map<String, Object?> toJson() =>
      payloadFor(createdAt: createdAt, keys: keys, suites: suites, v: v);

  /// The same payload as [toJson], for a package whose enrollment does not
  /// exist yet.
  ///
  /// A key package riding `enroll:request` is built before the atServer has
  /// assigned an enrollment id, so there is no [KeyPackage] to build it from.
  /// Nothing is lost by that: the id was never part of the payload — the
  /// enrollment record carries it, and [fromPayload] injects it back on read.
  /// [suites] defaults to what [keys] can actually open. An overstated claim
  /// here is correctable, but only by the enrollment itself: `enroll:update`
  /// reaches `metadata` and is self-only, so nobody else can repair a package
  /// that advertises a construction its holder cannot open.
  ///
  /// ⚠️ **This used to add "no client sends that operation yet, so in practice
  /// the value written at `enroll:request` is the one peers seal to".** One
  /// does as of 2026-08-19: `KeyPackageMinting` republishes the package at
  /// startup whenever the configured key-establishment list has changed, so
  /// the value peers seal to is the latest published one, not the original.
  static Map<String, Object?> payloadFor({
    required DateTime createdAt,
    required List<PackageKey> keys,
    List<String>? suites,
    int v = currentVersion,
  }) =>
      {
        'v': v,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'keys': keys.map((k) => k.toJson()).toList(),
        'suites': suites ??
            SecretSharingAlgos.openableSuitesForAll(keys.map((k) => k.alg)),
      };

  /// Parses a stored key-package [payload] (from `metadata.keyPackage`),
  /// injecting the [enrollmentId] / [apkamId] the enclosing verb structure
  /// carried. Skips malformed entries in `keys` rather than throwing — a
  /// payload written by a newer client may carry key entries (or extra fields)
  /// this version does not understand.
  ///
  /// Throws [FormatException] if the fields this version requires are missing
  /// or of the wrong type.
  static KeyPackage fromPayload(
    Object? payload, {
    required String enrollmentId,
    String? apkamId,
  }) {
    if (payload is! Map) {
      throw FormatException('KeyPackage: expected a Map, got $payload');
    }
    final v = payload['v'];
    final createdAt = payload['createdAt'];
    final keys = payload['keys'];
    if (v is! int || createdAt is! String || keys is! List) {
      throw FormatException('KeyPackage: malformed payload $payload');
    }
    // Required: a package that names no suites says nothing about what its
    // holder can open, and guessing on its behalf is how a sender comes to
    // seal something the holder cannot unwrap. A non-String ENTRY is still
    // dropped rather than throwing, matching how unknown `keys` entries are
    // handled — a newer writer may name suites this build has never heard of.
    final declared = payload['suites'];
    if (declared is! List) {
      throw FormatException(
          'KeyPackage: payload declares no suites, so nothing can be sealed '
          'to it: $payload');
    }
    return KeyPackage(
      v: v,
      enrollmentId: enrollmentId,
      apkamId: apkamId,
      createdAt: DateTime.parse(createdAt),
      keys: keys.map(PackageKey.fromJson).whereType<PackageKey>().toList(),
      suites: declared.whereType<String>().toList(),
    );
  }
}
