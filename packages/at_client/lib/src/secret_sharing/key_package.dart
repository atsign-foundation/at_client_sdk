import 'dart:convert' show utf8;

import 'package:at_chops/at_chops.dart' show SHA256HashingAlgo;
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
  static String computeKid(String pub) {
    // SHA256HashingAlgo.hash returns the full digest as lowercase hex; the
    // first 16 hex chars are the first 8 bytes.
    return SHA256HashingAlgo().hash(utf8.encode(pub)).substring(0, 16);
  }

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

/// The X-Wing recipient key(s) one **APKAM keypair** advertises so that other
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

  KeyPackage({
    required this.enrollmentId,
    this.apkamId,
    required this.createdAt,
    required this.keys,
    this.v = currentVersion,
  });

  /// The addressing token for this key package: the [kid] of its
  /// enc-use key (the X-Wing public key a sender seals to). Null if the
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
  Map<String, Object?> toJson() => {
        'v': v,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'keys': keys.map((k) => k.toJson()).toList(),
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
    return KeyPackage(
      v: v,
      enrollmentId: enrollmentId,
      apkamId: apkamId,
      createdAt: DateTime.parse(createdAt),
      keys: keys.map(PackageKey.fromJson).whereType<PackageKey>().toList(),
    );
  }
}
