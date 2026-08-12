import 'package:at_auth/at_auth.dart' show apskKid;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:meta/meta.dart' show experimental;

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

  PackageKey({
    required this.use,
    required this.alg,
    required this.pub,
    String? kid,
  }) : kid = kid ?? computeKid(pub);

  /// First 8 bytes, hex-encoded, of the SHA-256 of the public key material.
  ///
  /// Delegates to at_auth's `apskKid` rather than repeating it: the `_apsk`
  /// advertisement and a key package spell an entry the same way, and a kid
  /// computed two ways is a verification failure with nothing to say for
  /// itself — both sides compile, and the mismatch surfaces only as an
  /// envelope that will not verify.
  static String computeKid(String pub) => apskKid(pub);

  Map<String, Object?> toJson() => {
        'kid': kid,
        'use': use,
        'alg': alg,
        'pub': pub,
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
    return PackageKey(kid: kid, use: use, alg: alg, pub: pub);
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
  /// Absent on packages written before this field existed, and
  /// [legacySuites] is what those meant.
  ///
  /// Derived from [keys] when the caller does not state it, never from the
  /// build's own [SecretSharingAlgos.suites]. That list is what this client can
  /// *produce and open given the right key*; what this package's holder can
  /// open is fixed by the keys it actually advertises. Defaulting to the former
  /// made a package advertising one KEM claim it could unwrap constructions
  /// built on the other.
  final List<String> suites;

  /// What a key package with no `suites` field is taken to support.
  ///
  /// Exactly the one suite that existed when such packages were written. It
  /// must never grow: adding to it would claim, on behalf of holders that
  /// never said so, that they can open something they cannot.
  static const List<String> legacySuites = [SecretSharingAlgos.xWingHpke];

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
  String? bestSuiteFor(List<String> senderSuites) {
    for (final suite in senderSuites) {
      if (suites.contains(suite)) return suite;
    }
    return null;
  }

  /// The addressing token for this key package: the [kid] of its
  /// enc-use key (the KEM public key a sender seals to). Null if the
  /// package advertises no key for [SecretSharingAlgos.keyAlgos].
  String? get kpid => bestKeyFor(SecretSharingAlgos.keyAlgos)?.kid;

  /// The first key in [supportedAlgos] order (strongest first) that this key
  /// package advertises for [use]. Returns null if the package and
  /// [supportedAlgos] have no algorithm in common.
  PackageKey? bestKeyFor(List<String> supportedAlgos,
      {String use = SecretSharingAlgos.useEnc}) {
    for (final alg in supportedAlgos) {
      for (final key in keys) {
        if (key.alg == alg && key.use == use) {
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
  /// that advertises a construction its holder cannot open. No client sends
  /// that operation yet, so in practice the value written at `enroll:request`
  /// is the one peers seal to.
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
    // Absent means a package written before the field existed, which supports
    // exactly what was available then. A non-String entry is dropped rather
    // than throwing, matching how unknown `keys` entries are handled: a newer
    // writer may name suites this build has never heard of.
    final declared = payload['suites'];
    return KeyPackage(
      v: v,
      enrollmentId: enrollmentId,
      apkamId: apkamId,
      createdAt: DateTime.parse(createdAt),
      keys: keys.map(PackageKey.fromJson).whereType<PackageKey>().toList(),
      suites: declared is List
          ? declared.whereType<String>().toList()
          : legacySuites,
    );
  }
}
