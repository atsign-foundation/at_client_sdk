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
/// The recipient unit is the APKAM keypair, not a client process: a key
/// package is identified by ([enrollmentId], [apkamId]). Several APKAM
/// keypairs may belong to one enrollment (the keyfile copied to another
/// device, each minting its own), so an enrollment can expose more than one.
///
/// Key packages are **enrollment-internal** — they live in the per-APKAM
/// enrollment record (written under that APKAM keypair's authenticated write)
/// and are discovered only via the gated `enroll:listfornamespace` verb (see
/// [EnrollmentDirectory]). They are **not** published and **not** separately
/// signed: the atServer vouches that a returned key package belongs to the
/// enrollment it is filed under. (Message authenticity is the per-envelope
/// APKAM signature, see EnvelopeSigning — unchanged.)
///
/// The wire form is the value stored at `metadata.keyPackages[<format-id>]`
/// in the enrollment record ([toJson] / [fromPayload]); [enrollmentId] and
/// [apkamId] are carried by the enclosing verb structure, not duplicated in
/// the payload.
@experimental
class KeyPackage {
  static const int currentVersion = 1;

  final int v;

  /// The enrollment this key package belongs to.
  final String enrollmentId;

  /// The APKAM keypair this key package belongs to, as reported by the verb.
  /// Null on a key package this client builds for its own registration — the
  /// atServer files it under whichever APKAM keypair authenticated the write.
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

  /// The value stored at `metadata.keyPackages[<format-id>]` — the payload
  /// only. [enrollmentId] / [apkamId] are carried by the enclosing verb
  /// structure (the enrollment and its APKAM-keypair entry), not repeated here.
  Map<String, Object?> toJson() => {
        'v': v,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'keys': keys.map((k) => k.toJson()).toList(),
      };

  /// Parses a stored key-package [payload] (from `metadata.keyPackages`),
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
